
VERSION = '1.2.5'

class CorkscrewDeploys < Formula
  desc "Deploy and run code on another machine"
  homepage "https://github.com/windborne/corkscrew"
  version VERSION

  if Hardware::CPU.intel?
    url "https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-#{VERSION}-osx-x86_64.tar.gz"
    sha256 "b78ddf91f7969ef6a415223786aa104f9a76dc8e59ec411090512b00fa7b5a25"
  else
    url "https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-#{VERSION}-osx-arm64.tar.gz"
    sha256 "d0ba074e849f08a48a38ac6e74875796355618a4ad16ca1ea4b4f70ccca65e62"
  end

  def install
    bin.install "corkscrew"
    lib.install Dir["lib/*"]
  end

  test do
    system "#{bin}/corkscrew", "--version"
  end
end
