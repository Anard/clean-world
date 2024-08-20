#!/bin/bash

files=( "/var/lib/portage/world" )
while read set; do
	[ ${set::1} = '@' ] && files=( ${files[*]} ${set:1} )
done < "/var/lib/portage/world_sets"

for i in ${!files[*]}; do
	[ ${files[$i]::1} = '/' ] || files[$i]="/etc/portage/sets/${files[$i]}"
	[ -f ${files[$i]} ] || unset ${files[$i]}
done

# Parameters
unset QUIET VERBOSE CHECK tmpFile
while [ "$#" -gt 0 ]; do
	case "$1" in
	 -[^-]*)
	 	params=( $( echo "$1" | grep -o [^-] | sed 's/^/-/' ) )
	 	;;
	 *)
	 	params=( $1 )
	 	;;
	esac

	for param in ${params[*]}; do
		case "$param" in
		 -h|--help)
	 		help=$( cat << HELP
Script for checking useless atoms recorded in world files and clean them
Usage : clean-world [OPTION|FILE] [...]

OPTIONS :
        -h|--help	Print this help and exit

        -q|--quiet	Run quietly
        -c|--check-only	List removeable atoms without trying to clean world
        
FILE : if set, script won't check world but will try to clean atoms listed in FILE

HELP
)
		 	echo "${help}"
		 	exit 0
		 	;;

		 -q|--quiet)
			QUIET='q'
			;;
		 -v|--verbose)
		 	VERBOSE='v'
		 	;;
		 -c|--check-only)
			CHECK=1
			;;
		 -*)
			echo "Unknown option $param"
			exit 255
			;;
		 *)
			if [ -r "$param" ]; then
				tmpFile=( "${tmpFile[*]}" "$param" )
			else
				echo "File $param isn't accesible"
				exit 255
			fi
			;;
		esac
	done
	shift
done

# Prepare deselect file
if ! [ $tmpFile ]; then
	tmpFile="/tmp/deselect"
	[ -f "${tmpFile}" ] && rm "${tmpFile}"

	for file in ${files[*]}; do
		[ $QUIET ] || ( echo "" && echo "- Checking ${file} -" )
		declare -A depends
		while read package; do
			if ! [[ "${package}" =~ ^[a-zA-Z0-9].* ]]; then
				[ $VERBOSE ] && echo "skipping line $package"

			else
				depends["${package}"]="$( qdepends -Qq $package )"

				if [ -n "${depends["${package}"]}" ]; then
		        	[ $VERBOSE ] && echo "checking ${package}..."
				    if [ -n "$( emerge -pqc $package )" ]; then
				    	[ $QUIET ] || echo "$package needs to stay in @world"

					elif [ -n "$( equery -q d $package )" ]; then
						echo "$package can be deselected safely (pushed by ${depends["${package}"]})"
						echo "$package" >> "${tmpFile}"
					fi
				fi
				depends["${package}"]="${depends["${package}"]%%:*}"
			fi
		done < "${file}"
	done
	
	# Ask for cleaning world
	echo
	while true; do
		read -p "You can find packages that can be deselected in ${tmpFile}. Do you want to remove packages from your world files now ? (y/N/e to manually edit file) : " ans
		case $ans in
		 [eE] )
		 	nano "${tmpFile}"
		 	;;
		 [yY] )
		 	break
		 	;;
		 [nN]|"" )
		 	exit 0
		 	;;
		 *)
		 	;;
		 esac
	done
fi

unset deselect
[ $CHECK ] && unset depends && exit 0

while read package; do
	deselect=( "${deselect[*]}" "${package}" )
done < "${tmpFile}"

# First depclean current installation
echo ""
[ $QUIET ] || echo "First, we will clean your current installation"
sudo emerge -ac${QUIET} || exit 1

# Clean world & backup
for package in ${deselect[*]}; do
	sudo sed -i".bak" "/^${package//\//\\\/}$/i ## pushed by ${depends["${package}"]}" ${files[*]}
	sudo sed -i "/^${package//\//\\\/}$/ s/^/#/" ${files[*]}
done

# Final check
res="$( emerge -pqc )"
while [ -n "$res" ]; do
	echo "Emerge found some package(s) to remove, you should reintegrate them in your world files. Select a file to edit or recover all and try again :"
	echo "$res"

	select ans in ${files[*]} "recover all" "try again"; do
		case $ans in
		 "recover all")
			for file in ${files[*]}; do
				sudo mv "${file}.bak" "${file}"
			done
			break
		 	;;
		 "try again")
		 	break
		 	;;
		 *)
		 	if [ -f ${ans} ]; then
		 		sudo nano ${ans}
		 	else echo "Invalid option ${ans}"
		 	fi
		 	;;
		esac
	done

	res="$( emerge -pqc )"
done

# Remove useless backup files
for file in ${files[*]}; do
	if [ -f "${file}.bak" ]; then
		[ -n "$( diff "${file}" "${file}.bak" )" ] || sudo rm "${file}.bak"
	fi
done

exit 0
