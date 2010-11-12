# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require File.dirname( __FILE__ ) + '/set_extensions'

s=Set.new

puts "Generating set"
until s.size==350_000
    s.add rand(500_000)
end

puts "Level 0"
str=s.pack(0)
puts "#{"%.3f" % (str.size/1024.0)}"
s2=Set.unpack( str, 0 )
fail unless s2==s
(Integer( ARGV[0] ) - 1).times do
    str=s.pack(0)
    s2=Set.unpack( str, 0 )
end

puts "Level 1"
str=s.pack(1)
puts "#{"%.3f" % (str.size/1024.0)}"
s2=Set.unpack( str, 1 )
fail unless s2==s
(Integer( ARGV[0] ) - 1).times do
    str=s.pack(1)
    s2=Set.unpack( str, 1 )
end

puts "Level 2"
str=s.pack(2)
puts "#{"%.3f" % (str.size/1024.0)}"
s2=Set.unpack( str, 2 )
fail unless s2==s
(Integer( ARGV[0] ) - 1).times do
    str=s.pack(2)
    s2=Set.unpack( str, 2 )
end

puts "Level 3"
str=s.pack(3)
puts "#{"%.3f" % (str.size/1024.0)}"
s2=Set.unpack( str, 3 )
fail unless s2==s
(Integer( ARGV[0] ) - 1).times do
    str=s.pack(3)
    s2=Set.unpack( str, 3 )
end
