#
# Copyright 2012-2014 Chef Software, Inc.
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
# version_list: url=https://ftp.osuosl.org/pub/gnu/automake/ filter=automake-*.tar.gz

name "automake"
default_version "1.18.1"

dependency "autoconf"
dependency "perl-thread-queue"

license "GPL-2.0"
license_file "COPYING"
skip_transitive_dependency_licensing true

version("1.18.1") { source sha256: "63e585246d0fc8772dffdee0724f2f988146d1a3f1c756a3dc5cfbefa3c01915" }

source url: "https://ftp.osuosl.org/pub/gnu/automake/automake-#{version}.tar.gz"

relative_path "automake-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  command "./configure" \
          " --prefix=#{install_dir}/embedded", env: env

  make "-j #{workers}", env: env
  make "install", env: env
end
