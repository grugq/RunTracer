# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'zlib'
require 'msgpack'
require 'set'

class Set

    # Add some packing methods to the basic Set class. This
    # dramatically reduces the space required to store Sets 
    # which are only Integers, but won't work otherwise.
    def pack( compression_level=3 )
        return "" if self.empty?
        case compression_level
        when 0
            deflated=Zlib::Deflate.deflate( Marshal.dump( self ) )
        when 1
            deflated=Zlib::Deflate.deflate( self.to_a.sort.to_msgpack )
        when 2
            bitstring='0'*(self.max+1)
            self.each {|e| bitstring[e]='1'}
            deflated=[bitstring].pack 'b*'
        when 3
            bitstring='0'*(self.max+1)
            self.each {|e| bitstring[e]='1'}
            deflated=Zlib::Deflate.deflate( [bitstring].pack('b*') )
        end
        "#{deflated.size}:#{compression_level},#{deflated}"
    end

    def self.unpack( str, compression_level=3 )
        return Set.new if str.empty?
        header,body=str.split(',',2)
        size, level=header.split(':')
        unless size.to_i==body.size
            raise ArgumentError, "Couldn't read packed string"
        end
        case Integer( compression_level )
        when 0
            Marshal.load( Zlib::Inflate.inflate( body ) )
        when 1
            Set.new( MessagePack.unpack(Zlib::Inflate.inflate(body)) )
        when 2
            bitstring=body.unpack('b*').first
            ary=[]
            (0...bitstring.size).each {|idx| ary << idx if bitstring[idx]==?1}
            Set.new( ary )
        when 3
            bitstring=Zlib::Inflate.inflate( body ).unpack('b*').first
            ary=[]
            (0...bitstring.size).each {|idx| ary << idx if bitstring[idx]==?1}
            Set.new( ary )
        end
    end

end

