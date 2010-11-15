# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'beanstalk-client'
require 'msgpack'
require 'oklahoma_mixer'

# As traces come in, maintain an iteratively reduced set which
# still has full coverage. Not as efficient as the greedy 
# algorithm, but it's 'free' since we're processing the traces
# anyway. This reduced set can be greedily reduced further once
# we have enough coverage.
class IterativeReducer

    COMPONENT="IterativeReducer"
    VERSION="1.0.0"
    PREFIX="#{COMPONENT}-#{VERSION}"
    DEFAULTS={
        :beanstalk_servers=>["127.0.0.1"],
        :beanstalk_port=>11300,
        :backup_file=>"ccov-reduced.tch",
        :ringbuffer_size=>100,
        :debug=>true
    }

    def debug_info( str )
        warn "#{PREFIX}: #{str}" if @debug
    end

    def initialize( opt_hsh )
        @opts=DEFAULTS.merge( opt_hsh )
        @debug=@opts[:debug]
        @processed=0
        @coverage=Set.new
        @reduced={}
        servers=@opts[:beanstalk_servers].map {|srv_str| "#{srv_str}:#{@opts[:beanstalk_port]}" }
        debug_info "Starting up, connecting to #{@opts[:beanstalk_servers].join(' ')}"
        @stalk=Beanstalk::Pool.new servers
        @stalk.watch 'compressed'
        @stalk.use 'reduced'
        debug_info "Initializing backup in #{@opts[:backup_file]}"
        initialize_backup
        debug_info "Startup done."
    end

    def initialize_backup
        @backup=OklahomaMixer.open( @opts[:backup_file], :rcnum=>10 )
    end

    def close
        @backup.close
    end

    def coverage
        @coverage.size
    end

    def reduced_size
        @reduced.size
    end

    def update_rolling_average( added )
        @ringbuffer||=[]
        @ringbuffer << added
        @ringbuffer.shift if @ringbuffer.size > @opts[:ringbuffer_size]
        @avg=(@ringbuffer.inject {|s,x| s+=x} / @ringbuffer.size.to_f)
    end

    def rolling_average
        @avg
    end

    def update_reduced( this_set, fn )
        this_hsh={}
        # General Algorithm
        # There are two ways into the reduced set.
        # 1. Add new blocks
        # 2. Consolidate the blocks of 2 or more existing files

        unless this_set.subset? @coverage # then we add new blocks
            this_set_unique=(this_set - @coverage)
            update_rolling_average( this_set_unique.size )
            @coverage.merge this_set_unique
            # Any old files with unique blocks that
            # are covered by this set can be deleted 
            # and their unique blocks merged with those of this set
            # (this is breakeven at worst)
            @reduced.delete_if {|fn, hsh|
                this_set_unique.merge( hsh[:unique] ) if hsh[:unique].subset?( this_set ) 
            }
            this_hsh[:unique]=this_set_unique
            @reduced[fn]=this_hsh
        else # Do we consolidate 2 or more sets of unique blocks?
            update_rolling_average( 0 )
            double_covered=@reduced.select {|fn,hsh|
                hsh[:unique].subset? this_set
            }
            if double_covered.size > 1
                merged=Set.new
                double_covered.each {|fn,hsh|
                    merged.merge hsh[:unique]
                    @reduced.delete fn
                }
                this_hsh[:unique]=merged
                @reduced[fn]=this_hsh
            end
        end
        @backup['set']=@reduced.keys.to_msgpack
    end

    def process_next
        debug_info "getting next trace"
        job=@stalk.reserve # from 'compressed' tube
        message=MessagePack.unpack( job.body )
        deflated=Set.new( MessagePack.unpack(message['deflated']) )
        debug_info "Updating reduced"
        update_reduced( deflated, message['filename'])
        message.delete 'deflated'
        @stalk.put message.to_msgpack #into 'reduced' tube
        @processed+=1
        debug_info "Finished. Reduced Set: #{reduced_size} Total Cov: #{coverage}, Rolling Avg: #{rolling_average}, Processed: #{@processed}"
        job.delete
    end

end
