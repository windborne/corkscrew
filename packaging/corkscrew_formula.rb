
VERSION = '1.2.0'

class CorkscrewDeploys < Formula
  desc "Deploy and run code on another machine"
  homepage "https://github.com/windborne/corkscrew"
  version VERSION

  if Hardware::CPU.intel?
    url "https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-#{VERSION}-osx-x86_64.tar.gz"
    sha256 "e10c6237084d40db5c2f15a26af55e95b7ca6fa6c6993a604d5f2a35f6b7a374"
  else
    url "https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-#{VERSION}-osx-arm64.tar.gz"
    sha256 "230003b60bfdf851d23ee83d2c94598595ce1e82a82816dc7d93fa0a94a42cec"
  end

  def install
    bin.install "corkscrew"
    lib.install Dir["lib/*"]
  end

  test do
    system "#{bin}/corkscrew", "--version"
  end
end
