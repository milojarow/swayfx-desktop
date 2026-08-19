#!/bin/bash
# Directorio temporal para almacenar los datos
CACHE_DIR="$HOME/.cache/command-finder"
COMMANDS_FILE="$CACHE_DIR/commands.txt"

# Crear directorio cache si no existe
mkdir -p "$CACHE_DIR"

# Función para extraer keybindings directamente de los archivos de configuración
extract_keybindings() {
    echo "# Atajos de Teclado de Sway" > "$COMMANDS_FILE"
    echo "" >> "$COMMANDS_FILE"
    
    # Buscar en todos los archivos de configuración
    find ~/.config/sway -type f -name "*.conf" -o -name "default" -o -name "resize" -o -name "shutdown" -o -name "screenshot" | while read file; do
        grep -E '^\$bindsym' "$file" | while read line; do
            # Extraer la tecla y la acción
            key=$(echo "$line" | sed -E 's/^\$bindsym ([^#]*)(#.*)?$/\1/' | sed 's/  */ /g' | sed 's/^ *//g' | sed 's/ *$//g')
            
            # Buscar si hay un comentario del tipo ## Action // Description ## arriba de esta línea
            desc=$(grep -B 1 -E "^\$bindsym $key" "$file" | grep -E '##.*##' | head -1 | sed -E 's/^.*## ([^\/]+) \/\/ ([^\/]+)( \/\/ .*)?##.*$/\1 :: \2/')
            
            if [ -z "$desc" ]; then
                # Si no hay comentario, usar la acción del comando
                action=$(echo "$line" | sed -E 's/^\$bindsym [^ ]+ +exec +([^#]*).*$/\1/' | sed 's/  */ /g' | sed 's/^ *//g' | sed 's/ *$//g')
                if [ -z "$action" ]; then
                    action=$(echo "$line" | sed -E 's/^\$bindsym [^ ]+ +([^#]*).*$/\1/' | sed 's/  */ /g' | sed 's/^ *//g' | sed 's/ *$//g')
                fi
                echo "$action [$key]" >> "$COMMANDS_FILE"
            else
                # Usar la descripción encontrada
                echo "$desc [$key]" >> "$COMMANDS_FILE"
            fi
        done
    done
    
    # Eliminar duplicados y ordenar
    sort -u "$COMMANDS_FILE" -o "$COMMANDS_FILE"
}

# Generar la lista de comandos
extract_keybindings

# Mostrar los comandos en rofi
selection=$(cat "$COMMANDS_FILE" | rofi -dmenu -i -p "Buscar comando:" \
                                        -markup-rows \
                                        -no-custom \
                                        -width 80 \
                                        -lines 15 \
                                        -font "JetBrainsMono NF 12" \
                                        -theme-str 'window {width: 900px;}' \
                                        -theme-str 'listview {lines: 12;}' \
                                        -theme-str 'entry {placeholder: "Escribe para filtrar comandos...";}'
)

exit 0
