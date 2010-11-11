# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'msgpack'
require 'oklahoma_mixer'
require 'redis'
require 'beanstalk-client'
require File.dirname( __FILE__ ) + '/set_extensions'

class TraceCompressor

    COMPONENT="TraceCompressor"
    VERSION="1.0.0"
    PREFIX="#{COMPONENT}-#{VERSION}"

    def initialize 
        initialize_lookups
    end

    def initialize_lookup
        @tc=OklahomaMixer.open("test-lookup.tch", :rcnum=>2_000_000)
        @redis=Redis.new( :host=>@opts[:redis_server], :port=>@opts[:redis_port] )
    end

    def close_databases
        @tc.close
        @redis.close
    end

    def tc_deflate!( set )
        # Single thread / core only!
        changes={}
        current=Integer( @tc.store('idx', 0, :add) )
        added=0
        set.map! {|elem|
            unless (idx=@tc[elem]) #already there
                added+=1
                changes[(current+added)]=elem
                changes[elem]=(current+added)
                current+added
            else
                Integer( idx )
            end
        }
        @tc.transaction do
            @tc.update changes
            @tc.store 'idx', added, :add
        end
        set
    end

    def redis_store( word )
        # Safe concurrent access to the Redis DB
        loop do
            @redis.watch("words")
            value = @redis.hget("words", word)
            @redis.unwatch and break(value) if value
            idx = (@redis.hlen("words")/2).to_s
            break(idx) if @redis.multi do
                @redis.hmset("words", word, idx, idx, word)
            end
        end
    end


    def redis_deflate!( set )
        set.map! {|elem|
            Integer( redis_store(elem) )
        }
        set
    end

    def redis_inflate! set
        set.map! {|elem|
            @redis.hget("words", word)
        }
    end

    def tc_inflate! set
        set.map! {|elem|
            @tc[elem]
        }
    end

    def deflate!( set, lookup_type )
        case lookup_type
        when :tc
            tc_deflate! set 
        when :redis
            redis_deflate! set 
        end
    end

    def inflate!( set, lookup_type )
        case lookup_type
        when :tc
            tc_inflate! set 
        when :redis
            redis_inflate! set 
        end
    end

    def debug_info( str )
        warn "#{PREFIX}: #{str}" if @debug
    end

    def create_set( output, lookup_type )
        set=Set.new( output )
        raise "#{PREFIX}: Set size should match array size from tracer" unless set.size==output.size
        debug_info "#{set.size} elements in Set"
        deflate! set, lookup_type
        set
    end

    def compress_trace( trace, lookup_type )
        set=create_set( trace, lookup_type )
        covered=set.size
        packed=set.pack
        debug_info "compressed trace with #{covered} blocks to #{"%.2f" % (packed.size/1024.0)}KB"
        [covered, packed]
    end

    def decompress_trace( packed_trace, lookup_type )
        set=Set.unpack packed_trace
        inflate! set, lookup_type
    end

end

puts "Getting some traces"

bs=Beanstalk::Pool.new ['127.0.0.1:11300']
bs.watch "traced"
test_traces=[]
10.times do
    job=bs.reserve
    pdu=MessagePack.unpack( job.body )
    test_traces << pdu['trace_output'] # an array
    job.release
end

puts "Got them."

codec=TraceCompressor.new

test_traces.each {|test|
    "Starting test with a trace #{test.size}"
    # compress with TC
    mark=Time.now
    covered, packed=codec.compress_trace( test, :tc )
    puts "TC Compress in #{Time.now - mark}"
    assert_equal covered, test.size
    s1=Set.new test
    s2=compressor.decompress_trace packed, :tc
    puts "TC Decompress in #{Time.now - mark}"
    assert_equal s1, s2
    # compress with TC
    mark=Time.now
    covered, packed=codec.compress_trace( test, :redis )
    puts "Redis Compress in #{Time.now - mark}"
    assert_equal covered, test.size
    s1=Set.new test
    s2=compressor.decompress_trace packed, :redis
    puts "Redis Decompress in #{Time.now - mark}"
    assert_equal s1, s2
}
puts "Done."


    
