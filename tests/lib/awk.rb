# Copyright (c) 2011-2015, 2017 CrystaX.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are
# permitted provided that the following conditions are met:
#
#    1. Redistributions of source code must retain the above copyright notice, this list of
#       conditions and the following disclaimer.
#
#    2. Redistributions in binary form must reproduce the above copyright notice, this list
#       of conditions and the following disclaimer in the documentation and/or other materials
#       provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY CrystaX ''AS IS'' AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
# FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL CrystaX OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# The views and conclusions contained in the software and documentation are those of the
# authors and should not be interpreted as representing official policies, either expressed
# or implied, of CrystaX.

require 'open3'
require 'rbconfig'

require_relative 'log'
require_relative 'tests'

class AwkTests < Tests
  def initialize(ndk, options = {})
    super(ndk, options.merge(type: 'build'))

    @tests = Dir.glob(File.join(@ndk, 'tests', 'awk', '*')).sort

    case RUBY_PLATFORM
    when /linux/
      tag = 'linux'
    when /darwin/
      tag = 'darwin'
    when /(cygwin|mingw|win32)/
      tag = 'windows'
    else
      raise "Unknown RUBY_PLATFORM: #{RUBY_PLATFORM}"
    end

    if RUBY_PLATFORM =~ /linux/
      ft = `file -b /bin/ls`.chomp
      if ft =~ /64-bit/
        harch = 'x86_64'
      elsif ft =~ /32-bit/
        harch = 'x86'
      else
        harch = RbConfig::CONFIG['host_cpu']
      end
    else
      harch = RbConfig::CONFIG['host_cpu']
      harch = 'x86' if harch =~ /^i\d86$/
    end
    archs = [harch]
    archs << 'x86' if harch == 'x86_64'

    archs.each do |arch|
      if tag == 'windows' && arch == 'x86'
        host_tag = 'windows'
      else
        host_tag = "#{tag}-#{arch}"
      end
      awk = File.join(@ndk, 'prebuilt', host_tag, 'bin', "awk#{".exe" if RUBY_PLATFORM =~ /(cygwin|mingw|win32)/}")
      @awk = awk if @awk.nil? && File.exists?(awk)
    end
    raise "Can't find 'awk' in #{@ndk}" if @awk.nil?
  end

  def run
    @tests.each do |t|
      sname = File.basename(t)
      Log.notice "RUN awk test: #{sname}"

      script = File.join(@ndk, 'build', 'awk', "#{sname}.awk")
      raise "Missing AWK script: #{script}" unless File.exists?(script)

      Dir.glob(File.join(@ndk, 'tests', 'awk', sname, '*.in')).sort.each do |input|
        output = input.gsub(/\.in$/, '.out')
        raise "Missing AWK output file: #{output}" unless File.exists?(output)

        cmd = "#{@awk} -f \"#{script}\""
        Log.info "## COMMAND: #{cmd} < #{input}"
        os,es,st = Open3.capture3(cmd, stdin_data: File.read(input))
        raise es unless st.success?
        raise "AWK test #{sname} failed" if (os <=> File.read(output)) != 0
      end
    end
  end
end
