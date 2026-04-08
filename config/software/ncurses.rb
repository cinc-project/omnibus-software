#
# Copyright 2012-2019, Chef Software Inc.
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

name "ncurses"
default_version "6.6"

license "MIT"
license_file "http://invisible-island.net/ncurses/ncurses-license.html"
license_file "http://invisible-island.net/ncurses/ncurses.faq.html"
skip_transitive_dependency_licensing true

dependency "config_guess"

# versions_list: https://ftp.osuosl.org/pub/gnu/ncurses/ filter=*.tar.gz
version("6.6") { source sha256: "355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11" }

source url: "https://ftp.osuosl.org/pub/gnu/ncurses/ncurses-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "ncurses-#{version}"

########################################################################
#
# wide-character support:
# Ruby 1.9 optimistically builds against libncursesw for UTF-8
# support. In order to prevent Ruby from linking against a
# package-installed version of ncursesw, we build wide-character
# support into ncurses with the "--enable-widec" configure parameter.
# To support other applications and libraries that still try to link
# against libncurses, we also have to create non-wide libraries.
#
# The methods below are adapted from:
# http://www.linuxfromscratch.org/lfs/view/development/chapter06/ncurses.html
#
########################################################################

build do
  env = with_standard_compiler_flags(with_embedded_path)
  env.delete("CPPFLAGS")

  update_config_guess

  if mac_os_x? ||
      # Clang became the default compiler in FreeBSD 10+
      (freebsd? && ohai["os_version"].to_i >= 1000024)
    # References:
    # https://github.com/Homebrew/homebrew-dupes/issues/43
    # http://invisible-island.net/ncurses/NEWS.html#t20110409
    #
    # Patches ncurses for clang compiler. Changes have been accepted into
    # upstream, but occurred shortly after the 5.9 release. We should be able
    # to remove this after upgrading to any release created after June 2012
    patch source: "ncurses-clang.patch", env: env
  end

  configure_command = [
    "./configure",
    "--prefix=#{install_dir}/embedded",
    "--enable-overwrite",
    "--with-shared",
    "--with-termlib",
    "--without-ada",
    "--without-cxx-binding",
    "--without-debug",
    "--without-manpages",
  ]

  command configure_command.join(" "), env: env

  make "-j #{workers}", env: env
  make "-j #{workers} install", env: env

  # Build non-wide-character libraries
  make "distclean", env: env
  configure_command << "--enable-widec"

  command configure_command.join(" "), env: env
  make "-j #{workers}", env: env

  # Installing the non-wide libraries will also install the non-wide
  # binaries, which doesn't happen to be a problem since we don't
  # utilize the ncurses binaries in private-chef (or oss chef)
  make "-j #{workers} install", env: env
end
