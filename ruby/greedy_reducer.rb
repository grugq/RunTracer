# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

# Quick script to take a set of filenames which have already been traced
# and dump the greedy reduced minset filenames into another file.
# In Prospector, iterative_reduction_worker.rb would produce a first 
# pass reduction, which would be a suitable input into this script.

require 'rubygems'
require 'trollop'
require 'msgpack'
require File.dirname( __FILE__ ) + '/tracedb_api'
require File.dirname( __FILE__ ) + '/reductions'

OPTS=Trollop::options do
    opt :tracedb, "Trace DB file to use", :type=>:string, :default=>"ccov-traces.tch"
    opt :infile, "Reduced trace DB", :type=>:string
    opt :outfile, "Filename to use for output", :type=>:string
end

include Reductions

trace_db=TraceDB.new( OPTS[:tracedb], "re" )
reduced_db=OklahomaMixer.open( OPTS[:infile], "re" )
filenames=MessagePack.unpack(reduced_db['set'])
sample={}

filenames.each {|fn|
    sample.merge! trace_db.get_trace( fn )
}
raise "#{__FILE__}: Can't find all traces in the trace DB" unless sample.size==filenames.size

puts "Greedy reducing #{sample.size} from #{trace_db.traces}"
mark=Time.now
minset, coverage=greedy_reduce( sample )
puts "Dumping sample Minset #{minset.size}, covers #{coverage.size} - #{"%.2f" % (Time.now - mark)} secs"
File.open( OPTS[:outfile], "wb+" ) {|ios|
    sample.each {|fn, hsh|
        ios.puts fn
    }
}
