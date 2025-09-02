
VERSION = '1.1.2'

class CorkscrewDeploys < Formula
  desc "Deploy and run code on another machine"
  homepage "https://github.com/windborne/corkscrew"
  version VERSION

  if Hardware::CPU.intel?
    url "https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-#{VERSION}-osx-x86_64.tar.gz"
    sha256 "5864d818fdca8a494606c8d0b1eeb9b44c267700836ebd0576250c0d5ac70a55"
  else
    url "https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-#{VERSION}-osx-arm64.tar.gz"
    sha256 "f85846ed3928307846938632e80b79c62615f129ca32d54be2a8701903665137"
  end

  def install
    bin.install "corkscrew"
    lib.install Dir["lib/*"]
  end

  test do
    system "#{bin}/corkscrew", "--version"
  end
end
