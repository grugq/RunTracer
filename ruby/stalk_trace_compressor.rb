# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'beanstalk-client'
require 'msgpack'
require File.dirname( __FILE__ ) + '/trace_codec'

class StalkTraceCompressor

    COMPONENT="StalkTraceCompressor"
    VERSION="1.0.0"
    PREFIX="#{COMPONENT}-#{VERSION}"
    DEFAULTS={
        :beanstalk_servers=>["127.0.0.1"],
        :beanstalk_port=>11300,
        :lookup_file=>"ccov-lookup.tch",
        :debug=>true
    }

    def debug_info( str )
        warn "#{PREFIX}: #{str}" if @debug
    end

    def initialize( opt_hsh )
        @opts=DEFAULTS.merge( opt_hsh )
        @debug=@opts[:debug]
        servers=@opts[:beanstalk_servers].map {|srv_str| "#{srv_str}:#{@opts[:beanstalk_port]}" }
        debug_info "Starting up, connecting to #{@opts[:beanstalk_servers].join(' ')}"
        @stalk=Beanstalk::Pool.new servers
        initialize_codec
        debug_info "Codec initialized"
        @stalk.watch 'traced'
        @stalk.use 'compressed'
        debug_info "Startup done."
    end

    def initialize_codec
        @codec=TraceCodec.new( @opts[:lookup_file] )
    end

    def close
        @codec.close
    end

    def compress_next
        debug_info "getting next trace"
        job=@stalk.reserve # from 'traced' tube
        message=MessagePack.unpack( job.body )
        debug_info "compressing trace"
        deflated=@codec.deflate_set( @codec.set_to_trace(message['trace_output']) )
        covered, packed=@codec.pack_set( deflated )
        response={
            'covered'=>covered,
            'packed'=>packed, # this is for insertion into the DB
            'deflated'=>deflated.to_a.to_msgpack, # this will get used by the iterative reducer
            'filename'=>message['filename'], 
            'result'=>message['result']
        }.to_msgpack
        @stalk.put response # to 'compressed' tube
        debug_info "Finished."
        job.delete
    end

end
