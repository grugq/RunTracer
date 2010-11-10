# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'beanstalk-client'
require 'msgpack'
require 'oklahoma_mixer'
require File.dirname( __FILE__ ) + '/set_extensions'

class StalkTraceCompressor

    COMPONENT="StalkTraceCompressor"
    VERSION="1.0.0"

    attr_reader :processed_count

    def initialize( beanstalk_servers, beanstalk_port, store, debug )
        @debug=debug
        servers=beanstalk_servers.map {|srv_str| "#{srv_str}:#{beanstalk_port}" }
        debug_info "Starting up, connecting to #{beanstalk_servers.join(' ')}"
        @stalk=Beanstalk::Pool.new servers
        @lookup=OklahomaMixer.open("#{store}-lookup.tch", :rcnum=>1_000_000)
        debug_info "Opened database..."
        @stalk.watch 'traced'
        @stalk.use 'compressed'
    end

    def close_database
        @lookup.close
    end

    def deflate( set )
        changes={}
        current=Integer( @lookup.store('idx', 0, :add) )
        added=0
        set.map! {|elem|
            unless (idx=@lookup[elem]) #already there
                added+=1
                changes[(current+added)]=elem
                changes[elem]=(current+added)
                current+added
            else
                Integer( idx )
            end
        }
        @lookup.transaction do
            @lookup.update changes
            @lookup.store 'idx', added, :add
        end
        set
    rescue
        puts $!
        raise $!
    end

    def debug_info( str )
        warn "#{COMPONENT}-#{VERSION}: #{str}" if @debug
    end

    def create_set( output )
        set=Set.new(output)
        raise "#{COMPONENT}-#{VERSION}: Set size should match array size from tracer" unless set.size==output.size
        debug_info "#{set.size} elements in Set"
        mark=Time.now
        deflate set
        debug_info "Deflated in #{Time.now - mark} seconds."
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
    rescue
        raise $!
    end

end
