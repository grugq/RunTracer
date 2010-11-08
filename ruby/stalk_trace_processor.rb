require 'rubygems'
require 'zlib'
require 'beanstalk-client'
require 'msgpack'
require 'oklahoma_mixer'


class Set

    def pack
        bitstring='0'*(self.max+1)
        self.each {|e| bitstring[e]='1'}
        Zlib::Deflate.deflate( [bitstring].pack('b*') )
    end

    def self.unpack( str )
        bitstring=Zlib::Inflate.inflate( str ).unpack('b*').first
        ary=[]
        (0...bitstring.size).each {|idx| ary << idx if bitstring[idx]==?1}
        Set.new( ary )
    end

end

class StalkTraceProcessor

    COMPONENT="StalkTraceProcessor"
    VERSION="1.0.0"

    attr_reader :processed_count

    def initialize( servers, port, work_dir, debug, storename="ccov" )
        @work_dir=work_dir
        @debug=debug
        @storename=storename
        servers=servers.map {|srv_str| "#{srv_str}:#{port}" }
        debug_info "Starting up, connecting to #{servers.join(' ')}"
        setup_store
        @processed_count=0
        @stalk=Beanstalk::Pool.new servers
        @stalk.watch 'traced'
    end

    def setup_store
        @lookup=OklahomaMixer.open( "#{@storename}-lookup.tch", :rcnum=>100_000 )
        @traces=OklahomaMixer.open( "#{@storename}-traces.tch" )
    end

    def deflate( set )
        @lookup.transaction do
            set.map! {|elem|
                unless (idx=@lookup[elem]) #already there
                    idx=@lookup.store 'idx', 1, :add
                    @lookup.store elem, idx
                    @lookup.store idx, elem
                end
                idx
            }
        end
    end

    def inflate( set )
        # fetch raises if the key isn't present
        set.map {|elem| @lookup.fetch elem}
    end

    def debug_info( str )
        warn "#{COMPONENT} : #{VERSION}: #{str}" if @debug
    end

    def create_set( output )
        lines=output.split("\n")
        debug_info "#{lines.size} lines in trace"
        this_trace=Set.new
        lines.each {|l|
            from,to,count=l.split
            from="NOMODULE" if from[0]=='?'
            to="NOMODULE" if to[0]=='?'
            this_trace.add "#{from}=>#{to}".to_sym
        }
        debug_info "#{this_trace.size} elements in Set"
        deflate this_trace
    end

    def save_trace( filename, trace )
        packed_trace=create_set( trace ).pack
        debug_info "Storing packed trace #{packed_trace.size/1024}KB"
        @traces.store filename, packed_trace
    end

    def process_next
        debug_info "getting next trace"
        job=@stalk.reserve # from 'traced' tube
        pdu=MessagePack.unpack( job.body )
        debug_info "Saving trace"
        save_trace pdu['filename'], pdu['trace_output'] 
        job.delete
        @processed_count+=1
    rescue
        raise $!
    end

end
