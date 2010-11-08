require 'rubygems'
require 'trollop'
require 'win32/process'
require 'windows/window'
require 'sys/proctable'
require 'win32api'
require 'fileutils'
require File.dirname(__FILE__) + '/cpumon'

class WordTracer

    COMPONENT="WordTracer"
    VERSION="1.0.0"
    PINPATH="C:\\pin\\pin.bat"
    DLLPATH="C:\\runtracer\\obj-ia32\\ccovtrace.dll"
    WORDPATH="C:\\Program Files\\Microsoft Office\\Office12\\WINWORD.EXE"
    RETRY_COUNT=5

    include Windows::Error
    include Windows::Window
    include Windows::Process
    include Windows::Handle

    BMCLICK=0x00F5
    WM_DESTROY=0x0010
    WM_COMMAND=0x111
    IDOK=1
    IDCANCEL=2
    IDNO=7
    IDCLOSE=8
    GW_ENABLEDPOPUP=0x0006
    FindWindow=Win32API.new("user32.dll", "FindWindow", 'PP','N')
    GetWindow=Win32API.new("user32.dll", "GetWindow", 'LI','I')
    PostMessage=Win32API.new("user32.dll", "PostMessage", 'LILL','I')

    def start_dk_thread
        debug_info "Starting DK thread" if @debug
        @dk_thread.kill if @dk_thread
        @dk_thread=Thread.new do
            loop do
                sleep 1 
                begin
                    word_hwnd=FindWindow.call("OpusApp",0)
                    # Get any descendant windows which are enabled - alerts, dialog boxes etc
                    child_hwnd=GetWindow.call(word_hwnd, GW_ENABLEDPOPUP)
                    unless child_hwnd==0
                        PostMessage.call(child_hwnd,WM_COMMAND,IDCANCEL,0)
                        PostMessage.call(child_hwnd,WM_COMMAND,IDNO,0)
                        PostMessage.call(child_hwnd,WM_COMMAND,IDCLOSE,0)
                        PostMessage.call(child_hwnd,WM_COMMAND,IDOK,0)
                        PostMessage.call(child_hwnd,WM_DESTROY,0,0)
                    end
                    # The script changes the caption, so this should only detect toplevel dialog boxes
                    # that pop up during open before the main Word window.
                    toplevel_box=FindWindow.call(0, "Microsoft Office Word")
                    unless toplevel_box==0
                        PostMessage.call(toplevel_box,WM_COMMAND,IDCANCEL,0)
                        PostMessage.call(toplevel_box,WM_COMMAND,IDNO,0)
                        PostMessage.call(toplevel_box,WM_COMMAND,IDCLOSE,0)
                        PostMessage.call(toplevel_box,WM_COMMAND,IDOK,0)
                    end
                rescue
                    warn "#{COMPONENT}:#{VERSION}: Error in DK thread: #{$!}"
                    retry
                end
            end
        end
    end

    def sweep
        @patterns||=['R:/Temp/**/*.*', 'R:/Temporary Internet Files/**/*.*', 'R:/fuzzclient/~$*.doc', 'C:/stalktracer/~$*.doc']
        @patterns.each {|pattern|
            Dir.glob(pattern, File::FNM_DOTMATCH).each {|fn|
                next if File.directory?(fn)
                retry_count=RETRY_COUNT
                begin
                    FileUtils.rm_f(fn)
                rescue
                    if (retry_count-=1) <= 0
                        sleep 0.5
                        retry # probably still open
                    end
                    debug_info "#{__method__}: Exceeded retry count for #{fn}"
                end
            }
        }
    end

    def pids( caption )
        Sys::ProcTable.ps.to_a.select {|p|
            p.caption.upcase==caption.upcase
        }.map {|p| p.pid}
    end

    def kill_all( signal, pid_ary )
        pid_ary.each {|pid| Process.kill( signal, pid ) rescue nil }
    end

    def slay( caption )
        retry_count=RETRY_COUNT
        loop do
            return if (pids=pids( caption )).empty?
            kill_all 9, pids
            raise "#{COMPONENT}:#{VERSION}: #{__method__}( #{caption} ) exceeded retries." if (retry_count-=1) <= 0
            sleep 1
        end
    end

    def nicely_kill( caption )
        retry_count=RETRY_COUNT
        loop do
            return if (pids=pids( caption )).empty?
            kill_all 1, pids
            raise "#{COMPONENT}:#{VERSION}: #{__method__}( #{caption} ) exceeded retries." if (retry_count-=1) <= 0
            sleep 1
        end
    end

    def debug_info( str )
        warn "#{COMPONENT} : #{VERSION}: #{str}" if @debug
    end

    def pin_start( filename, modules )
        command_line="#{PINPATH} -t #{DLLPATH} #{modules.map {|modname| "-m #{modname} "}.join} -- \"#{WORDPATH}\" /q #{filename}"
        debug_info "Cmdline: #{command_line}"
        @pin_thread=Thread.new {system command_line}
    end

    def trace_output
        raise "#{COMPONENT}:#{VERSION}: Unable to read trace output file" unless File.exists? "trace.out"
        File.open( "trace.out", "rb" ) {|ios| ios.read} # could be empty...
    end

    def trace
        @cpumon=ProcessCPUMonitor.new( @this_word, thresh=10 )
        @start_time=Time.now
        begin
            until @cpumon.less_than_threshold?
                if Time.now - @start_time > @global_timeout
                    debug_info "Global timeout exceeded. Killing."
                    nicely_kill "WINWORD.EXE"
                    return 'hang'
                end
            end
            debug_info "CPU below threshold. Killing."
            nicely_kill "WINWORD.EXE"
            return 'success'
        rescue
            debug_info "Rescued #{$!}."
            nicely_kill( "WINWORD.EXE" ) rescue slay "WINWORD.EXE"
            slay "DW20.EXE"
            slay "pin.exe"
            return 'error'
        end
    end

    def initialize( filename, modules=[], global_timeout=300, debug=true )
        @debug=debug
        @global_timeout=global_timeout
        debug_info "New instance for #{filename}."
        debug_info "Whitelisting #{modules}" unless modules.empty?
        # ensure there are no other word processes running
        slay "WINWORD.EXE"
        slay "DW20.EXE"
        start_dk_thread
        # start process via pin (which threads out)
        pin_start( filename, modules )
        retry_count=RETRY_COUNT
        loop do
            @this_word=pids( "WINWORD.EXE" ).first
            break if @this_word
            if (retry_count-=1) <= 0
                slay "pin.exe"
                raise "#{COMPONENT}:#{VERSION}: #{__method__}( #{caption} ) exceeded retries."
            end
            sleep 1
        end
    rescue
        slay "WINWORD.EXE"
        slay "DW20.EXE"
        slay "pin.exe"
    end

    def close
        sweep
        @pin_thread && @pin_thread.kill
        @dk_thread && @dk_thread.kill
    end
end
