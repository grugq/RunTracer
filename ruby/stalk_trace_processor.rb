# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'beanstalk-client'
require 'msgpack'
require 'oklahoma_mixer'

class StalkTraceProcessor

    COMPONENT="StalkTraceProcessor"
    VERSION="1.0.0"

    attr_reader :processed_count

    def initialize( servers, port, storename, debug )
        @debug=debug
        @storename=storename
        servers=servers.map {|srv_str| "#{srv_str}:#{port}" }
        debug_info "Starting up, connecting to #{servers.join(' ')}"
        setup_store
        debug_info "Opened database..."
        @processed_count=0
        @stalk=Beanstalk::Pool.new servers
        @stalk.watch 'compressed'
    end

    def setup_store
        # Will reuse existing files if they are there
        @traces=OklahomaMixer.open( "#{@storename}-traces.tch" )
    end

    def has_file?( fname )
        @traces.has_key? "trc:#{fname}"
    end

    def debug_info( str )
        warn "#{COMPONENT}-#{VERSION}: #{str}" if @debug
    end

    def save_trace( filename, packed, covered, result )
        @traces.transaction do
            @traces.store "trc:#{filename}", packed
            @traces.store "blk:#{filename}", covered
            @traces.store "res:#{filename}", result
        end
    end

    def close_databases
        @traces.close
    end

    def process_next
        debug_info "getting next trace"
        job=@stalk.reserve # from 'compressed' tube
        pdu=MessagePack.unpack( job.body )
        debug_info "Saving trace of #{pdu['filename']}@#{"%.2f" % (pdu['packed'].size/1024.0)}KB -- #{pdu['covered']} blocks (#{pdu['result']})"
        save_trace pdu['filename'], pdu['packed'], pdu['covered'], pdu['result'] 
        job.delete
        @processed_count+=1
    rescue
        p pdu['covered']
        p pdu['packed'][0..100]
        raise $!
    end

end
