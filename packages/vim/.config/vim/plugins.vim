" =-=-=-=-=-=-=-=-=-=- Core =-=-=-=-=-=-=-=-=-=-

Plug 'tpope/vim-sensible'

"Plug 'Shougo/vimproc.vim', {'do' : 'make'}
"Plug 'ervandew/supertab'
Plug 'junegunn/vim-easy-align'
"Plug 'terryma/vim-multiple-cursors'
Plug 'mg979/vim-visual-multi', {'branch': 'master'}
"Plug 'haya14busa/vim-asterisk'
Plug 'AndrewRadev/undoquit.vim'
Plug 'wellle/targets.vim'
Plug 'editorconfig/editorconfig-vim'
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-sleuth'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-unimpaired'
Plug 'tpope/vim-repeat'
"Plug 'tpope/vim-dispatch'
Plug 'ap/vim-css-color'
"Plug 'jremmen/vim-ripgrep'
Plug 'dyng/ctrlsf.vim'
Plug 'ctrlpvim/ctrlp.vim'
"Plug 'nixprime/cpsm', { 'do': 'PY3=ON ./install.sh' }
"Plug 'http://github.com/sjl/gundo.vim'
Plug 'vim-scripts/IndentConsistencyCop'
Plug 'scrooloose/nerdcommenter'


" NERD tree
Plug 'scrooloose/nerdtree'
Plug 'jistr/vim-nerdtree-tabs'
Plug 'tiagofumo/vim-nerdtree-syntax-highlight'
"Plug 'her/synicons.vim'
Plug 'PhilRunninger/nerdtree-visual-selection'
Plug 'ryanoasis/vim-devicons'

" Fern
"Plug 'lambdalisue/fern.vim'
"Plug 'lambdalisue/nerdfont.vim'
"Plug 'lambdalisue/glyph-palette.vim'
"Plug 'lambdalisue/fern-renderer-nerdfont.vim'
"Plug 'lambdalisue/fern-hijack.vim'
"Plug 'LumaKernel/fern-mapping-fzf.vim'

Plug 'yssl/QFEnter'
"Plug 'mileszs/ack.vim'
"Plug 'jremmen/vim-ripgrep'
Plug 'Lokaltog/vim-easymotion'
Plug 'bronson/vim-visual-star-search'
"Plug 'milkypostman/vim-togglelist'
Plug 'valloric/listtoggle'
Plug 'janko/vim-test'
Plug 'liuchengxu/vista.vim'
"Plug 'skywind3000/asyncrun.vim'
"Plug 'tandrewnichols/vim-determined'
"Plug 'elbeardmorez/vim-loclist-follow' " doesn't work well

" Snippets
"Plug 'SirVer/ultisnips' " Fuck this shit
"Plug 'honza/vim-snippets'

" AutoComplete / Intellisense
"Plug '~/.vim/YouCompleteMe' " unmanaged

" Syntax checkers
"Plug 'scrooloose/syntastic'
"Plug 'w0rp/ale'
"Plug 'vim-syntastic/syntastic'

" Completions
"Plug 'maralla/completor.vim', {'do': 'cd pythonx/completers/javascript && npm install'}

" fzf
"Plug '/usr/local/opt/fzf'
"Plug 'junegunn/fzf.vim'

" Airline
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

" Themes
Plug 'dracula/vim'
Plug 'sonph/onehalf', { 'rtp': 'vim' }
Plug 'drewtempelmeyer/palenight.vim'

" Denite
if has('nvim')
  Plug 'Shougo/denite.nvim', { 'do': ':UpdateRemotePlugins' }
else
  Plug 'Shougo/denite.nvim'
  Plug 'roxma/nvim-yarp'
  Plug 'roxma/vim-hug-neovim-rpc'
endif


" Util/lib/Devel
Plug 'gioele/vim-autoswap'
Plug 'tomtom/tlib_vim'
Plug 'MarcWeber/vim-addon-mw-utils'
Plug 'vim-scripts/ingo-library'

" =-=-=-=-=-=-=-=-=-=- On Demand =-=-=-=-=-=-=-=-=-=-

" Languages
Plug 'sheerun/vim-polyglot'
"Plug 'evanleck/vim-svelte', { 'for': 'svelte'}
"Plug 'rust-lang/rust.vim', { 'for': 'rust' } " polyglot
Plug 'hashivim/vim-hashicorp-tools'
"Plug 'ternjs/tern_for_vim'
"Plug 'pangloss/vim-javascript' " polyglot
"Plug 'chemzqm/vim-jsx-improve'
"Plug 'stephpy/vim-yaml', { 'for': 'yaml' } "polyglot
"Plug 'wavded/vim-stylus', { 'for': 'stylus' } " polyglot
"Plug 'tikhomirov/vim-glsl', { 'for': 'glsl' } " polyglot
"Plug 'othree/html5.vim', { 'for': 'html' }
"Plug 'mxw/vim-jsx'
"Plug 'maxmellon/vim-jsx-pretty' " polyglot
"Plug 'Quramy/tsuquyomi', { 'for': 'typescript' }
"Plug 'leafgarland/typescript-vim', { 'for': 'typescript' } " polyglot
Plug 'HerringtonDarkholme/yats.vim', { 'for': 'typescript' }
"Plug 'joegesualdo/jsdoc.vim', { 'for': ['javascript', 'javascript.jsx', 'typescript'] }
"Plug 'heavenshell/vim-jsdoc', { 
	"\ 'for': ['javascript', 'javascript.jsx', 'typescript'], 
	"\ 'do': 'make install'
"\}
Plug 'pantharshit00/vim-prisma', { 'for': 'prisma' }
Plug 'heaths/vim-msbuild', { 'for': 'msbuild' }
"Plug 'peitalin/vim-jsx-typescript', { 'for': ['typescript', 'typescript.tsx' ] }


"Plug 'othree/yajs.vim'
"Plug 'othree/es.next.syntax.vim'
"Plug 'GutenYe/json5.vim', { 'for': 'json5' } " polyglot
"Plug 'elzr/vim-json', { 'for': ['json'] } " polyglot
"Plug 'kevinoid/vim-jsonc', { 'for': ['jsonc'] }
"Plug 'sukima/xmledit', { 'for': ['html', 'xml'] } " polyglot
"Plug 'skwp/vim-html-escape', { 'for': 'html' }
"Plug 'kchmck/vim-coffee-script', { 'for': 'coffeescript' } " coffeescript
"Plug 'ejholmes/vim-forcedotcom', { 'for': ['apex', 'visualforce'] }
"Plug 'juvenn/mustache.vim', { 'for': ['mustache', 'handlebars'] } " polyglot
"Plug 'chr4/nginx.vim', { 'for': 'nginx' }


" Themes
Plug 'mhartington/oceanic-next'
Plug 'morhetz/gruvbox'
Plug 'dracula/vim', { 'as': 'dracula' }
Plug 'whatyouhide/vim-gotham'
Plug 'altercation/vim-colors-solarized'
Plug 'audibleblink/hackthebox.vim'


" CoC

if has("nvim")
  Plug 'williamboman/mason.nvim'
else
  Plug 'neoclide/coc.nvim', {'branch': 'release'}
endif

" =-=-=-=-=-=-=-=-=-=- GUI =-=-=-=-=-=-=-=-=-=-

if has("gui_macvim") || has("nvim")

  Plug 'nathanaelkane/vim-indent-guides'


endif

