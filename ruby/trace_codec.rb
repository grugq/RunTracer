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
        raise "#{PREFIX}: Can't use this DB with implicit indexing!!" unless @lookup.size%2==0 
    end

    def close
        @lookup.close
    end

    def deflate_set( trace_set)
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

    def pack_set( deflated_set )
        covered=set.size
        packed=set.pack
        debug_info "Compressed trace with #{covered} blocks to #{"%.2f" % (packed.size/1024.0)}KB"
        [covered, packed]
    end

    def trace_to_set( trace_ary )
        set=Set.new( trace_ary )
        raise "#{PREFIX}: Set size should match Array size!" unless set.size==trace_ary.size
        debug_info "#{set.size} elements in Set"
    end

    def unpack_set( packed_set )
        Set.unpack( packed_set )
    end

    def inflate_set( trace_set )
        set.map! {|elem|
            @lookup[elem]
        }
    end

    def debug_info( str )
        warn "#{PREFIX}: #{str}" if @debug
    end

end
