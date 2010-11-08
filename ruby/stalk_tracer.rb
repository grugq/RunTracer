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

    def send_result( result, trace_output, filename )
        debug_info "Sending trace output (result #{result}) len #{trace_output.size/1024}KB"
        pdu={'result'=>result,'trace_output'=>trace_output, 'filename'=>filename}.to_msgpack
        @stalk.put pdu # to 'traced' tube
    end

    def trace_next
        begin
            job=@stalk.reserve # from 'untraced' tube
            pdu=MessagePack.unpack( job.body )
            debug_info "New trace, len #{pdu['data'].size/1024}KB"
            mark=Time.now if @debug
            fname=prepare_file( pdu['data'] )
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
