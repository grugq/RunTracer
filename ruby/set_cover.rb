# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'oklahoma_mixer'
require File.dirname( __FILE__ ) + '/set_extensions'

class TraceCodec

    COMPONENT="TraceCodec"
    VERSION="1.0.0"
    PREFIX="#{COMPONENT}-#{VERSION}"
    RCCACHE=2_000_000

    def initialize( lookup_filename="ccov-lookup.tch", mode="wc" )
        @lookup=OklahomaMixer.open( lookup_filename, mode, :rcnum=>RCCACHE)
    end

    def close
        @lookup.close
    end

    def compress_trace( trace_ary )
        set=create_set_from trace_ary
        covered=set.size
        packed=set.pack
        debug_info "Compressed trace with #{covered} blocks to #{"%.2f" % (packed.size/1024.0)}KB"
        [covered, packed]
    end

    def decompress_trace( packed_trace )
        set=Set.unpack packed_trace
        inflate! set
    end

    private

    def tc_deflate!( set )
        # Single thread / core only!
        cur=@lookup.size/2
        cached={}
        set.map! {|elem|
            unless (idx=@lookup[elem]) #already there
                raise "#{PREFIX}: Needed read/write access to deflate" if @lookup.read_only?
                cur+=1
                cached[cur]=elem
                cached[elem]=cur
                Integer( cur )
            else
                Integer( idx )
            end
        }
        @lookup.update cached unless cached.empty?
        set
    end

    def tc_inflate! set
        set.map! {|elem|
            @lookup[elem]
        }
    end

    def deflate!( set )
        tc_deflate! set 
    end

    def inflate!( set )
        tc_inflate! set 
    end

    def debug_info( str )
        warn "#{PREFIX}: #{str}" if @debug
    end

    def create_set_from( output )
        set=Set.new( output )
        raise "#{PREFIX}: Set size should match Array size!" unless set.size==output.size
        debug_info "#{set.size} elements in Set"
        deflate! set
    end

end
