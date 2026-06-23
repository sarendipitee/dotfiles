script_dir=$(realpath $(dirname $0))
packages_dir=$(realpath "$script_dir"/../packages)
dotfiles_dir=$(realpath "$script_dir/..")

# Initialize git submodules (for antidote, etc.)
cd "$dotfiles_dir" && git submodule update --init --recursive

dir_list="$packages_dir/*"

for dir in $dir_list; do
	package=$(basename $dir)
	packages="-R ${package} ${packages}"
done

stow \
	--verbose \
	--dotfiles \
	--ignore='\.gitignore$' \
	--override='.+' \
	--dir $packages_dir \
	--target $HOME \
	$packages
