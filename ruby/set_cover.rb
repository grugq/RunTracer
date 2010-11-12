# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'trollop'
require File.dirname( __FILE__ ) + '/trace_codec'

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
puts full.sort_by {|k,v| Integer( v[:covered] ) }[-10..-1].map {|fn, hsh| "#{fn}-#{hsh[:covered].to_i}"}
puts half.sort_by {|k,v| Integer( v[:covered] ) }[-10..-1].map {|fn, hsh| "#{fn}-#{hsh[:covered].to_i}"}

