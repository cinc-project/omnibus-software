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

name "perl"

license "Artistic-2.0"
license_file "Artistic"
skip_transitive_dependency_licensing true

default_version "5.42.2"

# versions_list: http://www.cpan.org/src/ filter=*.tar.gz
version("5.42.2") { source sha256: "9384e8deb75b7b1695e5637971b752281aaecd025a3d5d4734d33c1d0adfee47" }

source url: "https://www.cpan.org/src/5.0/perl-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

# perl builds perl as libraries into a special directory. We need to include
# that directory in lib_dirs so omnibus can sign them during macOS deep signing.
lib_dirs lib_dirs.concat ["#{install_dir}/embedded/lib/perl5/**"]

relative_path "perl-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  if freebsd? && ohai["os_version"].to_i >= 1000024
    cc_command = "-Dcc='clang'"
  elsif mac_os_x?
    cc_command = "-Dcc='clang'"
  else
    cc_command = "-Dcc='gcc -static-libgcc'"
  end

  configure_command = ["sh Configure",
                      " -de",
                      " -Dprefix=#{install_dir}/embedded",
                      " -Duseshrplib",
                      " -Dusethreads",
                      " #{cc_command}",
                      " -Dnoextensions='DB_File GDBM_File NDBM_File ODBM_File'"]

  command configure_command.join(" "), env: env
  make "-j #{workers}", env: env
  # using the install.perl target lets
  # us skip install the manpages
  make "install.perl", env: env
end
