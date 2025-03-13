
VERSION = '1.0.0'

class CorkscrewDeploys < Formula
  desc "Deploy and run code on another machine"
  homepage "https://github.com/windborne/corkscrew"
  url "https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-#{VERSION}-osx-x86_64.tar.gz"
  version VERSION
  sha256 "969c2923636ea20d5901c7fe918095e9a2711fe32bfb3233705919ca31f84701"

  def install
    bin.install "corkscrew"
    lib.install Dir["lib/*"]
  end

  test do
    system "#{bin}/corkscrew", "--version"
  end
end