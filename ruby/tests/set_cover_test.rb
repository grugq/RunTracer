# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'trollop'
require File.dirname( __FILE__ ) + '/../tracedb_api'
require File.dirname( __FILE__ ) + '/../reductions'

OPTS=Trollop::options do
    opt :file, "Trace DB file to use", :type=>:string, :default=>"ccov-traces.tch"
end

include Reductions

tdb=TraceDB.new OPTS[:file], "re"
full=tdb.sample_fraction(1)

fraction=1/128.0
samples=[]
until fraction > 1 
    samples << tdb.sample_fraction( fraction )
    fraction=fraction*2
end
tdb.close

puts "Collected samples, starting work"
samples.each {|sample|
    puts "Random sample of #{sample.size} from #{full.size}"
    mark=Time.now
    minset, coverage=greedy_reduce( sample )
    puts "Greedy: This sample Minset #{minset.size}, covers #{coverage.size} - #{"%.2f" % (Time.now - mark)} secs"
    mark=Time.now
    minset, coverage=iterative_reduce( sample )
    stage1=Time.now - mark
    puts "Iterative: This sample Minset #{minset.size}, covers #{coverage.size} - #{"%.2f" % stage1} secs"
    mark=Time.now
    minset, coverage=greedy_reduce( minset )
    stage2=Time.now - mark
    puts "Greedy Refined Iterative: This sample Minset #{minset.size}, covers #{coverage.size} - #{"%.2f" % (stage1+stage2)} secs"
}
