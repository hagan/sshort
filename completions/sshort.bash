# sshort bash completion
# Source this file or add to /etc/bash_completion.d/

_sshort_completions() {
    local cur prev words cword
    _init_completion || return

    local commands="init status clean remove config yubikey doctor help version commands shell-init sign add keygen"
    local config_commands="show edit init"
    local yubikey_commands="list"
    local validity_options="+1h +2h +4h +8h +12h +24h"
    local cert_options="source-address= no-port-forwarding no-agent-forwarding no-x11-forwarding no-pty force-command="

    # Get targets from config if available
    local targets=""
    if command -v sshort >/dev/null 2>&1; then
        targets=$(sshort config show 2>/dev/null | grep "^targets" | sed 's/.*= *//' | tr ',' ' ')
    fi

    case "${prev}" in
        sshort)
            COMPREPLY=($(compgen -W "${commands} ${targets} ${validity_options}" -- "${cur}"))
            return
            ;;
        status|st|clean|remove|rm|sign|add|keygen)
            COMPREPLY=($(compgen -W "all ${targets}" -- "${cur}"))
            return
            ;;
        config)
            COMPREPLY=($(compgen -W "${config_commands}" -- "${cur}"))
            return
            ;;
        yubikey|yk)
            COMPREPLY=($(compgen -W "${yubikey_commands}" -- "${cur}"))
            return
            ;;
        -O|--option)
            COMPREPLY=($(compgen -W "${cert_options}" -- "${cur}"))
            return
            ;;
    esac

    # Handle flags anywhere in the command
    if [[ "${cur}" == -* ]]; then
        COMPREPLY=($(compgen -W "-O --option -S --source-ip --principal= -h --help" -- "${cur}"))
        return
    fi

    # Handle validity patterns
    if [[ "${cur}" == +* ]]; then
        COMPREPLY=($(compgen -W "${validity_options}" -- "${cur}"))
        return
    fi

    # Default to targets and commands
    COMPREPLY=($(compgen -W "${commands} ${targets} ${validity_options}" -- "${cur}"))
}

complete -F _sshort_completions sshort
