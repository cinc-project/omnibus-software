#
# Copyright:: Chef Software, Inc.
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

name "stunnel"
default_version "5.78"

license "GPL-2.0"
license_file "COPYING"
skip_transitive_dependency_licensing true

dependency "openssl"

# version_list: url=https://www.stunnel.org/downloads/ filter=*.tar.gz

source url: "https://www.stunnel.org/archive/5.x/stunnel-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
           authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "stunnel-#{version}"

version("5.78") { source sha256: "8727e53bb8b7528f850327a2a149158422c02183bc120d1d733cc65b1e2c349d" }
version("5.77") { source sha256: "ec026f4fae4e0d25b940cc7a9451d925e359e7fd59e9edad20baea66ce45f263" }

build do
  env = with_standard_compiler_flags(with_embedded_path)

  patch source: "stunnel-on-windows-new.patch", plevel: 1, env: env if windows?

  configure_args = [
    "--with-ssl=#{install_dir}/embedded",
    "--prefix=#{install_dir}/embedded",
  ]
  configure_args << "--enable-fips" if fips_mode?

  configure(*configure_args, env: env)

  if windows?
    # src/mingw.mk hardcodes and assumes SSL is at /opt so we patch and use
    # an env variable to redirect it to the correct location
    env["WIN32_SSL_DIR_PATCHED"] = "#{install_dir}/embedded"

    mingw = ENV["MSYSTEM"].downcase
    target = (mingw == "mingw32" ? "mingw" : "mingw64")

    bin_dir = (mingw == "mingw32" ? "win32" : "win64")

    make target, env: env, cwd: "#{project_dir}/src"

    block "copy required windows files" do
      copy_files = %W{
        #{project_dir}/bin/#{bin_dir}/stunnel.exe
        #{project_dir}/bin/#{bin_dir}/tstunnel.exe}

      copy_files.each do |file|
        if File.exist?(file)
          copy file, "#{install_dir}/embedded/bin/#{File.basename(file)}"
        else
          raise "Cannot find required file for Windows: #{file}"
        end
      end
    end
  else
    make env: env
    make "install", env: env
  end
end
