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
    opt :lookup_file, "Use existing lookup file for the trace codec", :type=>:string, :default=>"ccov-lookup.tch"
    opt :debug, "Enable debug output", :type=>:boolean
end

compressor_opts={
    :beanstalk_servers=>OPTS[:servers],
    :beanstalk_port=>OPTS[:port],
    :lookup_file=>OPTS[:lookup_file],
    :debug=>OPTS[:debug]
}

compressor=StalkTraceCompressor.new compressor_opts

trap("INT") { compressor.close; exit }

loop do
    mark=Time.now if OPTS[:debug]
    compressor.compress_next
    warn "Elapsed Time: #{Time.now - mark}" if OPTS[:debug]
end
