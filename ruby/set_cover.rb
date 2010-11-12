# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'trollop'
require File.dirname( __FILE__ ) + '/trace_codec'
require File.dirname( __FILE__ ) + '/set_extensions'

OPTS=Trollop::options do
    opt :file, "Trace DB file to use", :type=>:string, :default=>"ccov-traces.tch"
end

class TraceDB

    def initialize( fname, mode )
        @db=OklahomaMixer.open fname, mode
        raise "Err, unexpected size for SetDB" unless @db.size%3==0
    end

    def traces
        @db.size/3
    end

    def sample_fraction( f )
        raise ArgumentError, "Fraction between 0 and 1" unless 0<f && f<=1
        cursor=(traces * f)-1
        key_suffixes=@db.keys( :prefix=>"trc:" ).shuffle[0..cursor].map {|e| e.split(':').last}
        hsh={}
        key_suffixes.each {|k|
            hsh[k]={
                :covered=>@db["blk:#{k}"],
                :trace=>@db["trc:#{k}"] #still packed.
            }
        }
        hsh
    end

end

tdb=TraceDB.new OPTS[:file], "re"
puts (full=tdb.sample_fraction(1)).size
puts (half=tdb.sample_fraction(0.5)).size

def greedy_reduce( set_hash )
    puts "Starting set #{set_hash.size}."
    candidates=set_hash.sort_by {|k,v| Integer( v[:covered] ) }
    minset=[]
    coverage=Set.new
    global_coverage=Set.new
    best_fn, best_hsh=candidates.pop
    minset.push best_fn

    # expand the starter set
    best_set=Set.unpack( first[:trace] )
    coverage=coverage.union( best_set )
    global_coverage=global_coverage.union( best_set )
    puts "Starting set #{coverage} elems"

    # strip elements from the candidates
    # This is outside the loop so we only have to expand
    # the sets to full size once.
    candidates.each {|fn, hsh|
        this_set=Set.unpack( hsh[:trace] )
        global_coverage=global_coverage.union( this_set )
        hsh[:set]=(this_set - best_set)
    }
    candidates.delete_if {|fn, hsh| hsh[:set].empty? }
    candidates=candidates.sort_by {|fn, hsh| hsh[:set].size }
    best_fn, best_hsh=candidates.pop
    minset.push best_fn
    best_set=best_hsh[:set]
    puts "Next best has #{best_set.size} elems left"
    coverage=coverage.union( best_set )

    # Now start the reduction loop, the Sets are expanded
    puts "Starting reduction"
    until candidates.empty?
        candidates.each {|fn, hsh|
            this_set=hsh[:set]
            hsh[:set]=(this_set - best_set)
        }
        candidates.delete_if {|fn, hsh| hsh[:set].empty? }
        candidates=candidates.sort_by {|fn, hsh| hsh[:set].size }
        best_fn, best_hsh=candidates.pop
        minset.push best_fn
        best_set=best_hsh[:set]
        coverage=coverage.union( best_set )
        puts "C:#{candidates.size} M:#{minset.size} ccov:#{coverage.size}"
    end
    raise "Bugger." unless coverage.size==global_coverage.size
    [minset, coverage]
end

puts "FULL: #{full.size} HALF: #{half.size}"
minset, coverage=greedy_reduce( full )
puts "FULL Minset #{minset.size}, covers #{coverage.size}"
minset, coverage=greedy_reduce( half )
puts "HALF Minset #{minset.size}, covers #{coverage.size}"
