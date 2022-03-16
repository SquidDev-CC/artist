(sources /src /spec)

(doc
  (json-index false)
  (destination /_site/)

  (site
    (title "artist")
    (source-link https://github.com/SquidDev-CC/artist/blob/${commit}/${path}#L${line}))

  (library-path /src/))

(at /
  (linters
    syntax:string-index
    -doc:undocumented-arg
    -doc:undocumented)

  (lint
    (globals
      :max sleep term colours keys fs turtle peripheral redstone textutils http parallel window
      write read)

    (bracket-spaces
      (call no-space)
      (function-args no-space)
      (parens no-space)
      (table space)
      (index no-space))))

(at /spec
  (lint
    (globals
      :max sleep term colours keys fs turtle peripheral redstone textutils http parallel window
      mcfly_seed expect stub describe it fail)))
