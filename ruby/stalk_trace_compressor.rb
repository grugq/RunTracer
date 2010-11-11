# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'beanstalk-client'
require 'msgpack'
require 'oklahoma_mixer'
require 'redis'
require File.dirname( __FILE__ ) + '/set_extensions'

class StalkTraceCompressor

    COMPONENT="StalkTraceCompressor"
    VERSION="1.0.0"
    PREFIX="#{COMPONENT}-#{VERSION}"
    DEFAULTS={
        :beanstalk_servers=>["127.0.0.1"],
        :beanstalk_port=>11300,
        :debug=>false,
        :lookup_type=>:tc,
        :redis_server=>"127.0.0.1",
        :redis_port=>6379,
        :lookup_file=>"ccov-lookup.tch",
        :debug=>OPTS[:debug]
    }
    TCCACHE=2_000_000 # Number of TokyoCabinet records to cache

    def initialize( opt_hsh )
        @opts=DEFAULTS.merge( opt_hsh )
        @debug=@opts[:debug]
        servers=@opts[:beanstalk_servers].map {|srv_str| "#{srv_str}:#{@opts[:beanstalk_port]}" }
        debug_info "Starting up, connecting to #{@opts[:beanstalk_servers].join(' ')}"
        @stalk=Beanstalk::Pool.new servers
        initialize_lookup
        debug_info "Opened database."
        @stalk.watch 'traced'
        @stalk.use 'compressed'
    end

    def initialize_lookup
        debug_info "Using lookup type #{@opts[:lookup_type]}"
        case @opts[:lookup_type]
        when :tc
            @lookup=OklahomaMixer.open(@opts[:lookup_file], :rcnum=>TCCACHE)
        when :redis
            @lookup=Redis.new( :host=>@opts[:redis_server], :port=>@opts[:redis_port] )
        else
            raise "#{PREFIX}: Unknown lookup type"
        end
    end

    def close_database
        @lookup.close
    end

    def redis_store( word )
        # Safe concurrent worker access to the Redis DB
        # but NOT for threads, need to add the :thread_safe
        # option to Redis.new for that.
        loop do
            @lookup.watch("words")
            value = @lookup.hget("words", word)
            @lookup.unwatch and break(value) if value
            idx = (@lookup.hlen("words")/2).to_s
            break(idx) if @lookup.multi do
                @lookup.hmset("words", word, idx, idx, word)
            end
        end
    end


    def redis_deflate!( set )
        set.map! {|elem|
            Integer( redis_store(elem) )
        }
    end

    def tc_deflate!( set )
        # Single thread / core only!
        cur=@lookup.size/2
        cached={}
        set.map! {|elem|
            unless (idx=@lookup[elem]) 
                cur+=1
                cached[cur]=elem
                cached[elem]=cur
                Integer( cur )
            else
                Integer( idx )
            end
        }
        @lookup.update cached
        set
    end

    def deflate!( set )
        case @opts[:lookup_type]
        when :tc
            tc_deflate! set 
        when :redis
            redis_deflate! set 
        end
    end

    def debug_info( str )
        warn "#{PREFIX}: #{str}" if @debug
    end

    def create_set( output )
        set=Set.new(output)
        raise "#{PREFIX}: Set size should match array size from tracer" unless set.size==output.size
        debug_info "#{set.size} elements in Set"
        mark=Time.now if @debug
        deflate! set
        debug_info "Deflated in #{Time.now - mark} seconds." if @debug
        set
    end

    def compress_trace( trace )
        set=create_set( trace )
        covered=set.size
        packed=set.pack
        debug_info "compressed trace with #{covered} blocks to #{"%.2f" % (packed.size/1024.0)}KB"
        [covered, packed]
    end

    def compress_next
        debug_info "getting next trace"
        job=@stalk.reserve # from 'traced' tube
        pdu=MessagePack.unpack( job.body )
        debug_info "compressing trace"
        covered, packed=compress_trace( pdu['trace_output'] ) 
        new_pdu={
            'covered'=>covered,
            'packed'=>packed, 
            'filename'=>pdu['filename'], 
            'result'=>pdu['result']
        }.to_msgpack
        @stalk.put new_pdu # to 'compressed' tube
        debug_info "Finished."
        job.delete
    end

end
