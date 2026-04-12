#
# Copyright 2022 Progress Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

name "ruby-msys2-devkit"
default_version "3.4.9-1"

license "BSD-3-Clause"
license_file "https://raw.githubusercontent.com/oneclick/rubyinstaller2/master/LICENSE.txt"
skip_transitive_dependency_licensing true
arch = "x64"
msys_dir = "msys64"

version "3.4.9-1" do
  source url: "https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-#{version}/rubyinstaller-devkit-#{version}-x64.exe",
          sha256: "39632975220ff43133244d8b8b8774feb0d301b33d11394513df28cb1853c36d"
  internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/rubyinstaller-devkit-#{version}-x64.exe",
                  authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"
end

build do
  if windows?
    embedded_dir = "#{install_dir}/embedded"

    Dir.mktmpdir do |tmpdir|
      command "#{project_dir}/rubyinstaller-devkit-#{version}-#{arch}.exe /SP- /NORESTART /VERYSILENT /SUPPRESSMSGBOXES /NOPATH /DIR=#{tmpdir}"
      copy "#{tmpdir}/#{msys_dir}", embedded_dir
      mkdir "#{embedded_dir}/lib/ruby/site_ruby/3.4.0"
      mkdir "#{embedded_dir}/lib/ruby/3.4.0/rubygems/defaults"
      copy "#{tmpdir}/lib/ruby/site_ruby/3.4.0/devkit.rb", "#{embedded_dir}/lib/ruby/site_ruby/3.4.0"
      copy "#{tmpdir}/lib/ruby/site_ruby/3.4.0/ruby_installer.rb", "#{embedded_dir}/lib/ruby/site_ruby/3.4.0"
      copy "#{tmpdir}/lib/ruby/site_ruby/3.4.0/ruby_installer", "#{embedded_dir}/lib/ruby/site_ruby/3.4.0"
      copy "#{tmpdir}/lib/ruby/3.4.0/rubygems/defaults", "#{embedded_dir}/lib/ruby/3.4.0/rubygems/defaults"

      # Normally we would symlink the required unix tools.
      # However with the introduction of git-cache to speed up omnibus builds,
      # we can't do that anymore since git on windows doesn't support symlinks.
      # https://groups.google.com/forum/#!topic/msysgit/arTTH5GmHRk
      # Therefore we copy the tools to the necessary places.
      # We need tar for 'knife cookbook site install' to function correctly and
      # many gems that ship with native extensions assume tar will be available
      # in the PATH.
      copy "#{tmpdir}/#{msys_dir}/usr/bin/bsdtar.exe", "#{install_dir}/bin/tar.exe"
      copy "#{tmpdir}/#{msys_dir}/usr/bin/msys-crypto-3.dll", "#{install_dir}/bin/msys-crypto-3.dll"
      copy "#{tmpdir}/#{msys_dir}/usr/bin/msys-bz2-1.dll", "#{install_dir}/bin/msys-bz2-1.dll"
      copy "#{tmpdir}/#{msys_dir}/usr/bin/msys-iconv-2.dll", "#{install_dir}/bin/msys-iconv-2.dll"
      copy "#{tmpdir}/#{msys_dir}/usr/bin/msys-expat-1.dll", "#{install_dir}/bin/msys-expat-1.dll"
      copy "#{tmpdir}/#{msys_dir}/usr/bin/msys-lzma-5.dll", "#{install_dir}/bin/msys-lzma-5.dll"
      copy "#{tmpdir}/#{msys_dir}/usr/bin/msys-lz4-1.dll", "#{install_dir}/bin/msys-lz4-1.dll"
      copy "#{tmpdir}/#{msys_dir}/usr/bin/msys-2.0.dll", "#{install_dir}/bin/msys-2.0.dll"
      copy "#{tmpdir}/#{msys_dir}/usr/bin/msys-z.dll", "#{install_dir}/bin/msys-z.dll"
      copy "#{tmpdir}/#{msys_dir}/usr/bin/msys-zstd-1.dll", "#{install_dir}/bin/msys-zstd-1.dll"
    end

    command "#{embedded_dir}/#{msys_dir}/msys2_shell.cmd -defterm -no-start -c exit", env: { "CONFIG" => "" }
  end
end
