require 'socket'
require 'json'

PORT = 3993
server = TCPServer.new PORT.to_s

puts "Booting dumb server on port #{PORT}"

while session = server.accept
  request = session.gets
  puts request

  session.print "HTTP/1.1 200\r\n"
  session.print "Content-Type: application/json\r\n"
  session.print "\r\n"
  session.print JSON.pretty_generate({ up: true, time: Time.now.to_s })

  session.close
end
