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

    def close
        @db.close
    end

    def sample_fraction( f )
        raise ArgumentError, "Fraction between 0 and 1" unless 0<f && f<=1
        cursor=(traces * f)-1
        key_suffixes=@db.keys( :prefix=>"trc:" ).shuffle[0..cursor].map {|e| e.split(':').last}.compact
        hsh={}
        key_suffixes.each {|k|
            hsh[k]={
                :covered=>@db["blk:#{k}"],
                :trace=>@db["trc:#{k}"] #still packed.
            }
            raise "DB screwed?" unless hsh[k][:covered] && hsh[k][:trace]
        }
        hsh
    end

    def method_missing meth, *args
        @db.send meth, *args
    end

end


module Reductions

    def greedy_refine( set_hsh )
        puts "Starting sample with #{set_hsh.size} sets"
        candidates=set_hsh.sort_by {|k,v| v[:full].size }
        minset=[]
        coverage=Set.new
        # General approach, with a list of sets sorted by size
        # Get best set, add to minset
        # Remove its elements from all remaining candidate sets
        # Drop any candidates which are now empty
        # Sort by size, repeat
        best_fn, best_hsh=candidates.pop
        minset.push [best_fn, best_hsh]

        # expand the starter set
        best_set=best_hsh[:full]
        coverage.merge best_set
        puts "Initial best set #{coverage.size} elems"

        candidates.each {|fn, hsh|
            hsh[:set]=(hsh[:full] - best_set)
        }
        candidates.delete_if {|fn, hsh| hsh[:set].empty? }
        candidates=candidates.sort_by {|fn, hsh| hsh[:set].size }
        best_fn, best_hsh=candidates.pop
        minset.push [best_fn, best_hsh]
        best_set=best_hsh[:set]
        puts "Next best has #{best_set.size} elems left"
        coverage.merge best_set 

        # Now start the reduction loop
        puts "Starting reduction"
        until candidates.empty?
            candidates.each {|fn, hsh|
                this_set=hsh[:set]
                hsh[:set]=(this_set - best_set)
            }
            candidates.delete_if {|fn, hsh| hsh[:set].empty? }
            candidates=candidates.sort_by {|fn, hsh| hsh[:set].size }
            best_fn, best_hsh=candidates.pop
            minset.push [best_fn, best_hsh]
            best_set=best_hsh[:set]
            coverage.merge best_set
        end
        [minset, coverage]

    end

    def update_minset( minset, coverage, fn, hsh )
        # There are two ways into the minset.
        # 1. Add new edges
        # 2. Consolidate the edges of 2 or more existing files
        this_set=Set.unpack( hsh[:trace] )
        # Do we add new edges?
        unless (this_set_unique=(this_set - coverage)).empty?
            coverage.merge this_set
            # Any old files with unique edges that
            # this full set covers can be deleted breakeven at worst
            minset.delete_if {|fn, hsh|
                hsh[:unique].subset? this_set
            }
            minset[fn]={:unique=>this_set_unique, :full=>this_set}
        else
            # Do we consolidate 2 or more sets of unique edges?
            double_covered=minset.select {|fn,hsh|
                hsh[:unique].subset? this_set
            }
            if double_covered.size > 1
                merged=Set.new
                double_covered.each {|fn,hsh|
                    merged.merge hsh[:unique]
                    minset.delete fn
                }
                minset[fn]={:unique=>merged, :full=>this_set}
            end
        end
    end

    def iterative_reduce( set_hash )
        puts "Starting sample with #{set_hash.size} sets"
        candidates=set_hash.to_a.shuffle
        minset={}
        coverage=Set.new
        # We're using each here, but the algorithm can be implemented
        # iteratively as traces come in.
        candidates.each {|fn, hsh|
            update_minset( minset, coverage, fn, hsh )
        }
        [minset, coverage]
    end

    def greedy_reduce( set_hash )
        puts "Starting sample with #{set_hash.size} sets"
        candidates=set_hash.sort_by {|k,v| Integer( v[:covered] ) }
        minset=[]
        coverage=Set.new
        best_fn, best_hsh=candidates.pop
        minset.push best_fn

        # expand the starter set
        best_set=Set.unpack( best_hsh[:trace] )
        coverage.merge best_set
        puts "Initial best set #{coverage.size} elems"

        # strip elements from the candidates
        # This is outside the loop so we only have to expand
        # the sets to full size once.
        candidates.each {|fn, hsh|
            this_set=Set.unpack( hsh[:trace] )
            hsh[:set]=(this_set - best_set)
        }
        candidates.delete_if {|fn, hsh| hsh[:set].empty? }
        candidates=candidates.sort_by {|fn, hsh| hsh[:set].size }
        best_fn, best_hsh=candidates.pop
        minset.push best_fn
        best_set=best_hsh[:set]
        puts "Next best has #{best_set.size} elems left"
        coverage.merge best_set 

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
            coverage.merge best_set
        end
        [minset, coverage]
    end

    def analyze_subsets( sample )
        sorted=sample.sort_by {|fn, hsh| hsh[:full].size}.reverse
        n=1
        until n > sorted.size
            coverage=Set.new
            sorted.slice(0,n).each {|fn, hsh|
                coverage.merge hsh[:full]
            }
            puts "Best #{n} of #{sample.size} covers #{coverage.size}"
            n*=2
        end
    end
end

include Reductions
tdb=TraceDB.new OPTS[:file], "re"
full=tdb.sample_fraction(1)
fraction=1/64.0
samples=[]
until fraction > 1 
    samples << tdb.sample_fraction( fraction )
    fraction=fraction*2
end
tdb.close
puts "Collected samples, starting work"
samples.each {|sample|
    puts "FULL: #{full.size} THIS: #{sample.size}"
    mark=Time.now
    minset, coverage=greedy_reduce( sample )
    puts "Greedy: This sample Minset #{minset.size}, covers #{coverage.size}"
    puts "Elapsed: #{Time.now - mark}"
    mark=Time.now
    minset, coverage=iterative_reduce( sample )
    puts "Iterative: This sample Minset #{minset.size}, covers #{coverage.size}"
    puts "Elapsed: #{Time.now - mark}"
    mark=Time.now
    minset, coverage=greedy_refine( minset )
    puts "Iterative + Greedy Refine: This sample Minset #{minset.size}, covers #{coverage.size}"
    puts "Elapsed: #{Time.now - mark}"
    analyze_subsets( minset )
}
