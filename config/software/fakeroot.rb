#
# Copyright 2016, Chef Software, Inc.
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
# version_list: url=https://deb.debian.org/debian/pool/main/f/fakeroot/ filter=fakeroot_*.orig.tar.gz

name "fakeroot"
default_version "1.37.2"

version("1.37.2") { source sha256: "0eea60fbe89771b88fcf415c8f2f0a6ccfe9edebbcf3ba5dc0212718d98884db" }

license "GPL-3.0"
license_file "COPYING"

source url: "https://deb.debian.org/debian/pool/main/f/fakeroot/fakeroot_#{version}.orig.tar.gz"

relative_path "fakeroot-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  configure_command = ["./configure",
                       "--prefix=#{install_dir}/embedded",
                       # This bit of magic is so we don't require the libcap library
                       "ac_cv_func_capset=no"]

  command configure_command.join(" "), env: env
  make "-j #{workers}", env: env
  make "-j #{workers} install", env: env
end
