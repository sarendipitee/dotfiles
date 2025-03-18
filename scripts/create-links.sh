script_dir=$(realpath $(dirname $0))
packages_dir=$(realpath "$script_dir"/../packages)

echo $script_dir
echo $packages_dir

dir_list="$packages_dir/*"

echo $dir_list

for dir in $dir_list; do
	package=$(basename $dir)
	packages="-R ${package} ${packages}"
done

stow -v --dotfiles -d $packages_dir -t $HOME $packages
