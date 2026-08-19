#!/bin/sh

case $1 in
  'status')
    # Obtiene la lista de actualizaciones disponibles (redirigiendo errores por si no existe)
    updates=$(checkupdates 2>/dev/null)

    # Si no hay actualizaciones, retorna JSON con 0
    if [ -z "$updates" ]; then
      printf '{"text":"0","tooltip":"System is up to date"}'
      exit 0
    fi

    count=$(printf '%s\n' "$updates" | wc -l)
    # Escapa los saltos de línea para JSON válido y escapa las comillas dobles
    escaped_updates=$(printf '%s' "$updates" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    # Imprime un JSON con el número de actualizaciones y la lista en el tooltip
    printf '{"text":"%s","tooltip":"%s"}' "$count" "$escaped_updates"
    ;;
  'check')
    # Retorna true si hay al menos una actualización
    [ $(checkupdates 2>/dev/null | wc -l) -gt 0 ]
    exit $?
    ;;
  'upgrade')
    # Intenta usar pacseek o topgrade si están disponibles, sino recurre a pacman
    if [ -x "$(command -v pacseek)" ]; then
      xdg-terminal-exec pacseek -u
    elif [ -x "$(command -v topgrade)" ]; then
      xdg-terminal-exec topgrade
    else
      xdg-terminal-exec pacman -Syu
    fi
    ;;
esac

