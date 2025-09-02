
VERSION = '1.1.2'

class CorkscrewDeploys < Formula
  desc "Deploy and run code on another machine"
  homepage "https://github.com/windborne/corkscrew"
  version VERSION

  if Hardware::CPU.intel?
    url "https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-#{VERSION}-osx-x86_64.tar.gz"
    sha256 "8c6048f273467ed9e4c3eb79aa893991315dbe3bed4e3f9a0cee2f1da1c1cf9c"
  else
    url "https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-#{VERSION}-osx-arm64.tar.gz"
    sha256 "7348a897703f613c36a5ad15916cd61dca54b6eabd7e0d987dfecf34255f43d2"
  end

  def install
    bin.install "corkscrew"
    lib.install Dir["lib/*"]
  end

  test do
    system "#{bin}/corkscrew", "--version"
  end
end
