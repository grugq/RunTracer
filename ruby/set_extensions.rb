# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'zlib'
require 'set'

class Set

    # Add some packing methods to the basic Set class. This
    # dramatically reduces the space required to store Sets 
    # which are only Integers, but won't work otherwise.
    def pack
        return "" if self.empty?
        bitstring='0'*(self.max+1)
        self.each {|e| bitstring[e]='1'}
        deflated=Zlib::Deflate.deflate( [bitstring].pack('b*') )
    end

    def self.unpack( str )
        return Set.new if str.empty?
        bitstring=Zlib::Inflate.inflate( str ).unpack('b*').first
        ary=[]
        (0...bitstring.size).each {|idx| ary << idx if bitstring[idx]==?1}
        Set.new( ary )
    end

end

