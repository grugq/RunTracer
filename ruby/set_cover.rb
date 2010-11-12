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
        raise ArgumentError, "Fraction between 0 and 1" unless 0<f<=1
        cursor=(traces * f)-1
        keys=@db.keys( :prefix=>"trc:" ).shuffle[0..cursor]
        Hash[ *(keys.zip( @db.values_at( keys )).flatten) ]
    end

end

tdb=TraceDB.new OPTS[:file], "re"
puts tdb.sample_fraction(1).size
puts tdb.sample_fraction(0.5).size
