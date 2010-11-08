require 'fileutils'
require File.dirname( __FILE__ ) + '/stalk_tracer'
require 'rubygems'
require 'trollop'

OPTS=Trollop::options do
    opt :port, "Port to connect to, default 11300", :type=>:integer, :default=>11300
    opt :servers, "Server to connect to, default 127.0.0.1", :type=>:strings, :default=>["127.0.0.1"]
    opt :work_dir, "Work dir, default C:\\stalktracer", :type=>:string, :default=>"C:\\stalktracer"
    opt :debug, "Enable debug output", :type=>:boolean
end

Dir.mkdir OPTS[:work_dir] unless File.directory? OPTS[:work_dir]

tracer=StalkTracer.new( OPTS[:servers], OPTS[:port], OPTS[:work_dir], OPTS[:debug] )

loop do
    tracer.trace_next
    # output general status, when implemented
end
