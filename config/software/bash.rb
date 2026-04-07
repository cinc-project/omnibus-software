#
# Copyright 2015 Chef Software, Inc.
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

name "bash"
default_version "5.3"

dependency "libiconv"
dependency "ncurses"
skip_transitive_dependency_licensing true

# version_list: url=https://ftp.osuosl.org/pub/gnu/bash/ filter=*.tar.gz

version("5.3") { source sha256: "0d5cd86965f869a26cf64f4b71be7b96f90a3ba8b3d74e27e8e9d9d5550f31ba" }

license "GPL-3.0"
license_file "COPYING"

source url: "https://ftp.osuosl.org/pub/gnu/bash/bash-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

# bash builds bash as libraries into a special directory. We need to include
# that directory in lib_dirs so omnibus can sign them during macOS deep signing.
lib_dirs lib_dirs.concat ["#{install_dir}/embedded/lib/bash"]

relative_path "bash-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  # FreeBSD can build bash with this patch but it doesn't work properly
  # Things like command substitution will throw syntax errors even though the syntax is correct
  patch source: "updated_race-condition.patch", plevel: 0, env: env

  configure_command = ["./configure",
                       "--prefix=#{install_dir}/embedded"]

  unless freebsd?
    # ncurses is built with --enable-widec which only installs wide-character
    # libraries (libncursesw, libtinfow). Additionally, --with-termlib splits
    # termcap functions (tputs, tgetent, etc.) into a separate libtinfow.
    # We must link against both libncursesw and libtinfow so bash's bundled
    # readline can resolve all termcap symbols from the embedded libraries
    # instead of picking up the non-wide system libtinfo.
    env["LIBS"] = "-ltinfow"
    configure_command << "bash_cv_termcap_lib=libncursesw"
  end

  if freebsd?
    # On freebsd, you have to force static linking, otherwise the executable
    # will link against the system ncurses instead of ours.
    configure_command << "--enable-static-link"

    # FreeBSD 12 system files come with mktime but for some reason running "configure"
    # doesn't detect this which results in a build failure. Setting this environment variable
    # corrects that.
    env["ac_cv_func_working_mktime"] = "yes"
  end

  command configure_command.join(" "), env: env
  make "-j #{workers}", env: env
  make "-j #{workers} install", env: env

  # We do not install bashbug in macos as it fails Notarization
  delete "#{install_dir}/embedded/bin/bashbug"
end
