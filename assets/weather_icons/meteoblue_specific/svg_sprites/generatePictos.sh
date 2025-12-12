# Convert pictogram SVG sprites into single files
# Requires command line inkscape, svg and gzip

#!/bin/bash
for theme in '' _monochrome _monochrome_hollow; do

	for pictoSet in iday day inight night; do

		if [ "$pictoSet" == "iday" ] || [ "$pictoSet" == "inight" ];
		then numberOfPictos=25;
		else numberOfPictos=37;
		fi

		for i in $(seq 1 $numberOfPictos); do

			name=$(printf %02d $i)_${pictoSet}${theme};
			echo $name;

			inkscape \
				--export-id=$name \
				--export-id-only \
				--export-plain-svg=../${name}.svg \
				--export-area-page \
				./weather_pictos${theme}.svg

			inkscape ../${name}.svg --vacuum-defs;

			svgo ../${name}.svg --config ./svgo-config.js --multipass -q

			gzip -9kvfn ../${name}.svg
		done

	done

done