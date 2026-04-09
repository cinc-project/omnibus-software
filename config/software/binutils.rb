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
# version_list: url=https://ftp.osuosl.org/pub/gnu/binutils/ filter=binutils-*.tar.gz

name "binutils"
default_version "2.46.0"

version("2.46.0") { source sha256: "8608fe44ab7de645f6ad0a898313b75338842490d609adb85c9fb2827c376af2" }

license "GPL-3.0"
license_file "COPYING"
license_file "COPYING.LIB"

source url: "https://ftp.osuosl.org/pub/gnu/binutils/binutils-#{version}.tar.gz"

relative_path "binutils-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  configure_command = ["./configure",
                     "--prefix=#{install_dir}/embedded",
                     "--disable-libquadmath",
                     "--disable-werror"]

  command configure_command.join(" "), env: env

  make "-j #{workers}", env: env
  make "-j #{workers} install", env: env
end