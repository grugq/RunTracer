# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require File.dirname(__FILE__) + "/word_tracer"
require 'rubygems'
require 'beanstalk-client'
require 'msgpack'

class StalkTracer

    COMPONENT="StalkTracer"
    VERSION="1.0.0"

    def initialize( servers, port, work_dir, debug )
        @work_dir=work_dir
        @debug=debug
        servers=servers.map {|srv_str| "#{srv_str}:#{port}" }
        debug_info "Starting up, connecting to #{servers.join(' ')}"
        @counter=0
        @stalk=Beanstalk::Pool.new servers
        @stalk.watch 'untraced'
        @stalk.use 'traced'
    end

    def debug_info( str )
        warn "#{COMPONENT} : #{VERSION}: #{str}" if @debug
    end

    def prepare_file( data )
        begin
            filename="trace-#{@counter+=1}.doc"
            path=File.join( File.expand_path(@work_dir), filename )
            File.open( path, "wb+" ) {|io| io.write data}
            path
        rescue
            raise RuntimeError, "Fuzzclient: Couldn't create test file #{filename} : #{$!}"
        end
    end

    def preprocess( trace_output )
        this_trace=Set.new
        trace_output.split("\n").each {|l|
            from,to,count=l.split
            from="OUT" if from[0]==?? # chr '?' on 1.9, ord 63 on 1.8
            to="OUT" if to[0]==??
            this_trace.add "#{from}=>#{to}"
        }
        this_trace.to_a
    end

    def send_result( result, trace_output, filename )
        trace_output=preprocess( trace_output )
        pdu={'result'=>result,'trace_output'=>trace_output, 'filename'=>filename}.to_msgpack
        debug_info "Sending trace output (result #{result}) len #{pdu.size/1024}KB"
        @stalk.put pdu # to 'traced' tube
    end

    def trace_next
        begin
            job=@stalk.reserve # from 'untraced' tube
            pdu=MessagePack.unpack( job.body )
            debug_info "New trace, len #{pdu['data'].size/1024}KB"
            mark=Time.now if @debug
            fname=prepare_file( pdu['data'] )
            # An option here would be to put an iterative version of
            # the blocking 'trace' method, so that we can touch the job
            # in between the CPU monitor ticks.
            wt=WordTracer.new( fname, pdu['modules'] )
            result=wt.trace
            debug_info "Elapsed time #{Time.now - mark}" if @debug
            send_result result, wt.trace_output, pdu['filename']
            wt.sweep
            job.delete
        rescue
            raise $!
        ensure
            FileUtils.rm_f fname rescue nil
            wt.close rescue nil
        end
    end

end
