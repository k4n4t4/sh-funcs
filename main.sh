#!/bin/sh
set -eu

base_name() {
  RET="$1"
  if [ "$RET" = "" ]; then
    RET="."
  else
    RET="${RET%"${RET##*[!/]}"}"
    RET="${RET##*/}"
    if [ "$RET" = "" ]; then
      RET="/"
    fi
  fi
}

base_name() {
  RET="${1:-}"
  case "$RET" in
    ( "" ) : ;;
    ( * )
      RET="${RET%"${RET##*[!"/"]}"}"
      case "$RET" in
        ( "" ) RET="/" ;;
        ( * ) RET="${RET##*"/"}" ;;
      esac
      ;;
  esac
}

abs_path() {
  TMP="$PWD"
  dir_name "$1"
  cd -- "$RET" || return 1
  base_name "$1"
  set -- "$PWD" "/" "$RET"
  case "$1" in
    ( "/" | "//" )
      set -- "$1" "" "$3"
      ;;
  esac
  case "$3" in
    ( "/" )  RET="$1$2" ;;
    ( "." | "" )  RET="$1" ;;
    ( ".." )
      cd ..
      RET="$PWD"
      ;;
    ( * ) RET="$1$2$3" ;;
  esac
  cd -- "$TMP" || return 1
}

cmd_exist() {
  if command -v -- "$1" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

is_empty_dir() {
  set -- "${1:-.}"
  set -- "$1"/* "$1"/.*
  while [ $# -gt 0 ]; do
    base_name "$1"
    case "$RET" in
      ( "." | ".." | "*" | ".*" ) shift 1 ;;
      ( * ) return 1 ;;
    esac
  done
  return 0
}

file_exist() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    return 0
  else
    return 1
  fi
}

is_broken_symlink() {
  if [ ! -e "$1" ] && [ -L "$1" ]; then
    return 0
  else
    return 1
  fi
}

is_number() {
  case "$1" in
    ( *[!0123456789]* )
      return 1
      ;;
    ( * )
      return 0
      ;;
  esac
}

is_int() {
  is_number "${1#"-"}"
}

qesc() {
  RET="$1"
  set -- ""
  while : ; do
    case "$RET" in
      ( *"'"* )
        set -- "$1${RET%%"'"*}'\\''"
        RET="${RET#*"'"}"
        ;;
      ( * )
        RET="'$1$RET'"
        break
        ;;
    esac
  done
}

opt_parser_get_arg_count() {
  RET="$1"
  eval "set -- $2"
  while [ $# -gt 0 ]; do
    case "$1" in
      ( "$RET:"?* )
        RET="${1#"$RET:"}"
        return 0
        ;;
    esac
    shift
  done
  RET=0
  return 0
}

opt_parser() {
  _opt_parser_options=""
  _opt_parser_normal_args=""
  _opt_parser_option_args=""

  while [ $# -gt 0 ]; do

    case "$1" in
      ( '--' )
        shift
        break
        ;;
      ( ?':'?* ) qesc "-$1" ;;
      ( ?*':'?* ) qesc "--$1" ;;
      ( ? ) qesc "-$1:1" ;;
      ( ?* ) qesc "--$1:1" ;;
      ( * )
        shift
        continue
        ;;
    esac

    _opt_parser_options="$_opt_parser_options $RET"
    shift
  done

  while [ $# -gt 0 ]; do
    case "$1" in
      ( '--' )
        shift
        break
        ;;
      ( '--'* | '-'? )
        case "$1" in ( "--"?*"="* )
          RET="$1"
          shift
          set -- "${RET%%"="*}" "${RET#*"="}" "$@"
          continue
        esac

        opt_parser_get_arg_count "$1" "$_opt_parser_options"
        _opt_parser_arg_count="$RET"

        if [ $# -gt "$_opt_parser_arg_count" ]; then
          while [ "$_opt_parser_arg_count" -ge 0 ]; do
            qesc "$1"
            _opt_parser_option_args="$_opt_parser_option_args $RET"
            shift
            _opt_parser_arg_count=$((_opt_parser_arg_count - 1))
          done
        else
          shift
        fi
        ;;
      ( '-'?* )
        opt_parser_get_arg_count "${1%"${1#??}"}" "$_opt_parser_options"
        if [ "$RET" -eq 1 ]; then
          RET="$1"
          shift
          set -- "${RET%"${RET#??}"}" "${RET#??}" "$@"
          continue
        fi

        _opt_parser_short_opts="${1#'-'}"
        while [ "$_opt_parser_short_opts" != "" ]; do
          _opt_parser_short_opt="-${_opt_parser_short_opts%"${_opt_parser_short_opts#?}"}"
          opt_parser_get_arg_count "$_opt_parser_short_opt" "$_opt_parser_options"
          if [ "$RET" -eq 0 ] && [ "$_opt_parser_short_opt" != '--' ]; then
            qesc "$_opt_parser_short_opt"
            _opt_parser_option_args="$_opt_parser_option_args $RET"
          fi
          _opt_parser_short_opts="${_opt_parser_short_opts#?}"
        done
        shift
        ;;
      ( * )
        qesc "$1"
        _opt_parser_normal_args="$_opt_parser_normal_args $RET"
        shift
        ;;
    esac
  done

  while [ $# -gt 0 ]; do
    qesc "$1"
    _opt_parser_normal_args="$_opt_parser_normal_args $RET"
    shift
  done

  RET="${_opt_parser_option_args#' '} -- ${_opt_parser_normal_args#' '}"
}

match() {
  RET="$1"
  eval "set -- $2"
  while [ $# -gt 0 ]; do
    eval 'case "$1" in ( '"$RET"' ) return 0 ;; esac'
    shift
  done
  return 1
}

alt_match() {
  RET="$1"
  eval "set -- $2"
  while [ $# -gt 0 ]; do
    eval 'case "$RET" in ( '"$1"' ) return 0 ;; esac'
    shift
  done
  return 1
}

true() {
  return 0
}

false() {
  return 1
}

get_files() {
  TMP=""
  for i in "$1"/* "$1"/.*; do
    base_name "$i"
    case "$RET" in ( ".." | "." | "*" | ".*" )
      continue
    esac
    qesc "$i"
    TMP="$TMP $RET"
  done
  RET="$TMP"
}

get_files_recursive() {
  TMP=""
  _dir_max_depth="${2:-1000}"
  _include_dir="${3:-false}"
  _dir_depth=0
  set -- "$1"
  while [ $# -gt 0 ]; do
    _dir_stack=""
    _dir_depth=$((_dir_depth + 1))
    while [ $# -gt 0 ]; do
      for i in "$1"/* "$1"/.*; do
        base_name "$i"
        case "$RET" in ( '.' | '..' | '*' | '.*' ) continue ;; esac
        if [ -d "$i" ] && [ "$_dir_depth" -ne "$_dir_max_depth" ]; then
          qesc "$i"
          _dir_stack="$_dir_stack $RET"
          if $_include_dir; then
            TMP="$TMP $RET"
          fi
        else
          qesc "$i"
          TMP="$TMP $RET"
        fi
      done
      shift
    done
    eval 'set -- "$@" '"$_dir_stack"
  done
  RET="$TMP"
}

_stack_params=""
push_params() {
  TMP=""
  while [ $# -gt 0 ]; do
    qesc "$1"
    TMP="$TMP $RET"
    shift
  done
  qesc "$TMP"
  _stack_params="$RET $_stack_params"
}

# shellcheck disable=SC2120
pop_params() {
  eval "set -- $_stack_params"
  TMP="$1"
  shift
  _stack_params=""
  while [ $# -gt 0 ]; do
    qesc "$1"
    _stack_params="$_stack_params $RET"
    shift
  done
  RET="$TMP"
}

push_val() {
  qesc "$2"
  eval "$1"'="$'"$1"' $RET"'
}

pop_val() {
  TMP="$1"
  eval 'RET="$'"$1"'"'
  eval "set -- $RET"
  while [ $# -gt 1 ]; do
    qesc "$1"
    eval "$TMP"'="$'"$TMP"' $RET"'
    shift
  done
  RET="$1"
}
