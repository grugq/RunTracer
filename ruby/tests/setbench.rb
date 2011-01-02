# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require File.dirname( __FILE__ ) + '/set_extensions_test'

S=Set.new

puts "Generating set"
until S.size==350_000
    S.add rand(500_000)
end

def bench( level, n )
    puts "Level #{level}"
    mark=Time.now
    str=S.pack( level )
    puts "#{"%.3f" % (str.size/1024.0)}KB"
    s2=Set.unpack( str, level )
    fail unless s2==S
    (n - 1).times do
        str=S.pack(level)
        s2=Set.unpack( str, level )
    end
    puts "Average #{(Time.now - mark)/n} secs"
end

(0..4).each {|level|
    bench( level, ARGV[0].to_i )
}
