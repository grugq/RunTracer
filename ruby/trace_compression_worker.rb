# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'trollop'
require File.dirname( __FILE__ ) + '/stalk_trace_compressor'

OPTS=Trollop::options do
    opt :port, "Beanstalk port to connect to", :type=>:integer, :default=>11300
    opt :servers, "Beanstalk servers to connect to", :type=>:strings, :default=>["127.0.0.1"]
    opt :name, "Name for the store files", :type=>:string, :default=>"ccov"
    opt :debug, "Enable debug output", :type=>:boolean
end

compressor=StalkTraceCompressor.new( OPTS[:servers], OPTS[:port], OPTS[:name], OPTS[:debug] )

trap("INT") { compressor.close_database; exit }

loop do
    compressor.compress_next
end
