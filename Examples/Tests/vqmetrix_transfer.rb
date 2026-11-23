#!/usr/bin/env ruby
# Exercise the actual upload implementation against local HTTP endpoints.
require 'fileutils'
require 'socket'
require 'tmpdir'
require 'timeout'

root = File.expand_path('../..', __dir__)
Dir.mktmpdir('vqmetrix-transfer-') do |directory|
  transfer = File.join(directory, 'VQMetrixTransfer.swift')
  FileUtils.cp(File.join(root, 'Examples', 'macOS', 'VQMetrixTransfer.swift'), transfer)
  executable = File.join(directory, 'probe')
  abort 'Swift compilation failed' unless system('xcrun', 'swiftc', '-target', 'arm64-apple-macos15.5',
    '-module-cache-path', File.join(directory, 'cache'), transfer,
    File.join(__dir__, 'VQMetrixTransferProbe.swift'), '-o', executable)
  servers = Array.new(5) { TCPServer.new('127.0.0.1', 0) }
  threads = servers.each_with_index.map do |server, index|
    Thread.new do
      (index == 0 ? 2 : 1).times do
        socket = server.accept
        begin
          headers = +''
          headers << socket.read(1) until headers.end_with?("\r\n\r\n")
          raise 'Invalid request path' unless headers.start_with?("POST /api/v1/runs HTTP/1.1\r\n")
          raise 'Missing authentication' unless headers.include?('Authorization: Bearer 1234')
          raise 'Missing protocol' unless headers.include?('X-VQMetrix-Protocol: 1')
          raise 'Run ID changed' unless headers.downcase.include?('idempotency-key: 12345678-1234-1234-1234-123456789abc')
          length = headers[/Content-Length: (\d+)/i, 1].to_i
          raise 'Wrong body length' unless length == 131_072 && socket.read(length)&.bytesize == length
          sleep 1 if index == 4
          body = case index
                 when 1 then '{}'
                 when 3 then 'x' * 100_000
                 else '{"jobId":"12345678-1234-1234-1234-123456789abc"}'
                 end
          status = index == 2 ? '302 Found' : '202 Accepted'
          socket.write("HTTP/1.1 #{status}\r\nLocation: http://127.0.0.1:1/\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        rescue Errno::EPIPE, Errno::ECONNRESET
          raise unless index == 3 || index == 4
        ensure
          socket.close
        end
      end
    end
  end
  pid = Process.spawn(executable, *servers.map { |server| server.addr[1].to_s })
  begin
    _, status = Timeout.timeout(60) { Process.wait2(pid) }
    abort 'Transfer probe failed' unless status.success?
    Timeout.timeout(5) { threads.each(&:value) }
  rescue Timeout::Error
    Process.kill('KILL', pid) rescue nil
    Process.wait(pid) rescue nil
    abort 'Transfer probe timed out'
  ensure
    servers.each(&:close)
    threads.each { |thread| thread.kill if thread.alive? }
  end
end
