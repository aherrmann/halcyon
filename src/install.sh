create_install_tag () {
	local prefix label source_hash \
		ghc_version ghc_magic_hash
	expect_args prefix label source_hash \
		ghc_version ghc_magic_hash -- "$@"

	create_tag "${prefix}" "${label}" "${source_hash}" '' '' \
		"${ghc_version}" "${ghc_magic_hash}" \
		'' '' '' '' \
		''
}


detect_install_tag () {
	local tag_file
	expect_args tag_file -- "$@"

	local tag_pattern
	tag_pattern=$( create_install_tag '.*' '.*' '.*' '.*' '.*' )

	local tag
	if ! tag=$( detect_tag "${tag_file}" "${tag_pattern}" ); then
		log_error 'Failed to detect install tag'
		return 1
	fi

	echo "${tag}"
}


derive_install_tag () {
	local tag
	expect_args tag -- "$@"

	local prefix label source_hash ghc_version ghc_magic_hash
	prefix=$( get_tag_prefix "${tag}" )
	label=$( get_tag_label "${tag}" )
	source_hash=$( get_tag_source_hash "${tag}" )
	ghc_version=$( get_tag_ghc_version "${tag}" )
	ghc_magic_hash=$( get_tag_ghc_magic_hash "${tag}" )

	create_install_tag "${prefix}" "${label}" "${source_hash}" \
		"${ghc_version}" "${ghc_magic_hash}"
}


format_install_id () {
	local tag
	expect_args tag -- "$@"

	local label source_hash
	label=$( get_tag_label "${tag}" )
	source_hash=$( get_tag_source_hash "${tag}" )

	echo "${source_hash:0:7}-${label}"
}


format_install_archive_name () {
	local tag
	expect_args tag -- "$@"

	local install_id
	install_id=$( format_install_id "${tag}" )

	echo "halcyon-install-${install_id}.tar.gz"
}


format_install_archive_name_prefix () {
	echo 'halcyon-install-'
}


format_install_archive_name_pattern () {
	local tag
	expect_args tag -- "$@"

	local label
	label=$( get_tag_label "${tag}" )

	echo "halcyon-install-.*-${label//./\.}.tar.gz"
}


install_extra_apps () {
	local tag source_dir install_dir
	expect_args tag source_dir install_dir -- "$@"

	if [[ ! -f "${source_dir}/.halcyon/extra-apps" ]]; then
		return 0
	fi

	local prefix
	prefix=$( get_tag_prefix "${tag}" )

	local ghc_version ghc_magic_hash
	ghc_version=$( get_tag_ghc_version "${tag}" )
	ghc_magic_hash=$( get_tag_ghc_magic_hash "${tag}" )

	local cabal_version cabal_magic_hash cabal_repo
	cabal_version=$( get_tag_cabal_version "${tag}" )
	cabal_magic_hash=$( get_tag_cabal_magic_hash "${tag}" )
	cabal_repo=$( get_tag_cabal_repo "${tag}" )

	local extra_constraints
	extra_constraints="${source_dir}/.halcyon/extra-apps-constraints"

	local -a opts_a
	opts_a=()
	opts_a+=( --prefix="${prefix}" )
	opts_a+=( --root="${install_dir}" )
	opts_a+=( --ghc-version="${ghc_version}" )
	opts_a+=( --cabal-version="${cabal_version}" )
	opts_a+=( --cabal-repo="${cabal_repo}" )
	[[ -e "${extra_constraints}" ]] && opts_a+=( --constraints="${extra_constraints}" )

	log 'Installing extra apps'

	local extra_app index
	index=0
	while read -r extra_app; do
		local thing
		if [[ -d "${source_dir}/${extra_app}" ]]; then
			thing="${source_dir}/${extra_app}"
		else
			thing="${extra_app}"
		fi

		index=$(( index + 1 ))
		if (( index > 1 )); then
			log
		fi

		# NOTE: Returns 2 if build is needed.
		HALCYON_INTERNAL_RECURSIVE=1 \
		HALCYON_INTERNAL_GHC_MAGIC_HASH="${ghc_magic_hash}" \
		HALCYON_INTERNAL_CABAL_MAGIC_HASH="${cabal_magic_hash}" \
		HALCYON_INTERNAL_NO_COPY_LOCAL_SOURCE=1 \
			halcyon install "${opts_a[@]}" "${thing}" 2>&1 | quote || return
	done <"${source_dir}/.halcyon/extra-apps" || return 0
}


install_extra_data_files () {
	expect_vars HALCYON_BASE

	local tag source_dir build_dir install_dir
	expect_args tag source_dir build_dir install_dir -- "$@"

	if [[ ! -f "${source_dir}/.halcyon/extra-data-files" ]]; then
		return 0
	fi

	expect_existing "${build_dir}/dist/.halcyon-data-dir" || return 1

	local data_dir
	data_dir=$( <"${build_dir}/dist/.halcyon-data-dir" ) || true
	if [[ -z "${data_dir}" ]]; then
		log_error 'Failed to read data directory file'
		return 1
	fi

	log_indent 'Installing extra data files'

	local glob
	while read -r glob; do
		copy_dir_glob_into "${build_dir}" "${glob}" "${install_dir}${data_dir}" || return 1
	done <"${source_dir}/.halcyon/extra-data-files" || return 0
}


install_extra_os_packages () {
	local tag source_dir install_dir
	expect_args tag source_dir install_dir -- "$@"

	if [[ ! -f "${source_dir}/.halcyon/extra-os-packages" ]]; then
		return 0
	fi

	local extra_packages prefix
	extra_packages=$( <"${source_dir}/.halcyon/extra-os-packages" ) || true
	prefix=$( get_tag_prefix "${tag}" )

	log 'Installing extra OS packages'

	if ! install_platform_packages "${extra_packages}" "${install_dir}${prefix}"; then
		log_error 'Failed to install extra OS packages'
		return 1
	fi
}


prepare_install_dir () {
	expect_vars HALCYON_BASE

	local tag source_dir constraints build_dir install_dir
	expect_args tag source_dir constraints build_dir install_dir -- "$@"

	expect_existing "${build_dir}/.halcyon-tag" "${build_dir}/dist/.halcyon-data-dir" || return 1

	local data_dir
	data_dir=$( <"${build_dir}/dist/.halcyon-data-dir" ) || true
	if [[ -z "${data_dir}" ]]; then
		log_error 'Failed to read data directory file'
		return 1
	fi

	local prefix label install_id label_dir
	prefix=$( get_tag_prefix "${tag}" )
	label=$( get_tag_label "${tag}" )
	label_dir="${install_dir}${prefix}/.halcyon/${label}"

	local -a copy_opts_a register_opts_a
	copy_opts_a=()
	copy_opts_a+=( --destdir="${install_dir}" )
	copy_opts_a+=( --verbose=0 )
	register_opts_a=()
	register_opts_a+=( --gen-pkg-config="${label_dir}/${label}.conf" )
	register_opts_a+=( --verbose=0 )

	log 'Preparing install directory'

	# NOTE: PATH is extended to silence a misleading Cabal warning.
	if ! PATH="${install_dir}${prefix}:${PATH}" \
			sandboxed_cabal_do "${build_dir}" copy "${copy_opts_a[@]}" 2>&1 | quote ||
		! mkdir -p "${label_dir}" ||
		! sandboxed_cabal_do "${build_dir}" register "${register_opts_a[@]}" 2>&1 | quote
	then
		log_error 'Failed to copy app to install directory'
		return 1
	fi

	# NOTE: Returns 2 if build is needed.
	install_extra_apps "${tag}" "${source_dir}" "${install_dir}" || return

	if ! install_extra_data_files "${tag}" "${source_dir}" "${build_dir}" "${install_dir}"; then
		log_error 'Failed to install extra data files'
		return 1
	fi

	# NOTE: Cabal libraries may require data files at run-time.
	# See filestore for an example.
	# https://haskell.org/cabal/users-guide/developing-packages.html#accessing-data-files-from-package-code
	if find_tree "${HALCYON_BASE}/sandbox/share" -type f |
		match_at_least_one >'/dev/null'
	then
		log 'Installing extra data files for dependencies'

		copy_dir_into "${HALCYON_BASE}/sandbox/share" "${install_dir}${HALCYON_BASE}/sandbox/share" || return 1
	fi

	install_extra_os_packages "${tag}" "${source_dir}" "${install_dir}" || return 1

	if [[ -f "${source_dir}/.halcyon/pre-install-hook" ]]; then
		log 'Executing pre-install hook'
		if ! HALCYON_INTERNAL_RECURSIVE=1 \
			"${source_dir}/.halcyon/pre-install-hook" \
				"${tag}" "${source_dir}" "${install_dir}" "${data_dir}" 2>&1 | quote
		then
			log_error 'Failed to execute pre-install hook'
			return 1
		fi
		log 'Pre-install hook executed'
	fi

	local executable
	if executable=$( detect_executable "${source_dir}" ); then
		if ! echo "${executable}" >"${label_dir}/executable"; then
			log_error 'Failed to prepare install directory'
			return 1
		fi
	fi

	local prepared_size
	if ! format_constraints <<<"${constraints}" >"${label_dir}/constraints" ||
		! echo "${data_dir}" >"${label_dir}/data-dir" ||
		! derive_install_tag "${tag}" >"${label_dir}/tag" ||
		! prepared_size=$( get_size "${install_dir}" )
	then
		log_error 'Failed to prepare install directory'
		return 1
	fi
	log "Install directory prepared, ${prepared_size}"

	if [[ -d "${install_dir}${prefix}/share/doc" ]]; then
		log_indent_begin 'Removing documentation from install directory...'

		local trimmed_size
		if ! rm -rf "${install_dir}${prefix}/share/doc" ||
			! trimmed_size=$( get_size "${install_dir}" )
		then
			log_indent_end 'error'
			return 1
		fi
		log_indent_end "done, ${trimmed_size}"
	fi

	if ! derive_install_tag "${tag}" >"${install_dir}/.halcyon-tag"; then
		log_error 'Failed to write install tag'
		return 1
	fi
}


archive_install_dir () {
	expect_vars HALCYON_NO_ARCHIVE \
		HALCYON_INTERNAL_PLATFORM

	local install_dir
	expect_args install_dir -- "$@"

	if (( HALCYON_NO_ARCHIVE )); then
		return 0
	fi

	expect_existing "${install_dir}/.halcyon-tag" || return 1

	local install_tag ghc_id archive_name
	install_tag=$( detect_install_tag "${install_dir}/.halcyon-tag" ) || return 1
	ghc_id=$( format_ghc_id "${install_tag}" )
	archive_name=$( format_install_archive_name "${install_tag}" )

	log 'Archiving install directory'

	create_cached_archive "${install_dir}" "${archive_name}" || return 1
	upload_cached_file "${HALCYON_INTERNAL_PLATFORM}/ghc-${ghc_id}" "${archive_name}" || return 1

	local archive_prefix archive_pattern
	archive_prefix=$( format_install_archive_name_prefix )
	archive_pattern=$( format_install_archive_name_pattern "${install_tag}" )

	delete_matching_private_stored_files "${HALCYON_INTERNAL_PLATFORM}/ghc-${ghc_id}" "${archive_prefix}" "${archive_pattern}" "${archive_name}" || return 1
}


validate_install_dir () {
	local tag install_dir
	expect_args tag install_dir -- "$@"

	local install_tag
	install_tag=$( derive_install_tag "${tag}" )
	detect_tag "${install_dir}/.halcyon-tag" "${install_tag//./\.}" || return 1
}


restore_install_dir () {
	expect_vars HALCYON_INTERNAL_PLATFORM

	local tag install_dir
	expect_args tag install_dir -- "$@"

	local ghc_id archive_name archive_pattern
	ghc_id=$( format_ghc_id "${tag}" )
	archive_name=$( format_install_archive_name "${tag}" )
	archive_pattern=$( format_install_archive_name_pattern "${tag}" )

	log 'Restoring install directory'

	if ! extract_cached_archive_over "${archive_name}" "${install_dir}" ||
		! validate_install_dir "${tag}" "${install_dir}" >'/dev/null'
	then
		rm -rf "${install_dir}" || true
		cache_stored_file "${HALCYON_INTERNAL_PLATFORM}/ghc-${ghc_id}" "${archive_name}" || return 1

		if ! extract_cached_archive_over "${archive_name}" "${install_dir}" ||
			! validate_install_dir "${tag}" "${install_dir}" >'/dev/null'
		then
			rm -rf "${install_dir}" || true

			log_error 'Failed to restore install directory'
			return 1
		fi
	else
		touch_cached_file "${archive_name}"
	fi
}


install_app () {
	expect_vars HALCYON_BASE HALCYON_ROOT \
		HALCYON_KEEP_DEPENDENCIES \
		HALCYON_INTERNAL_RECURSIVE

	local tag source_dir install_dir
	expect_args tag source_dir install_dir -- "$@"

	local prefix label install_id label_dir
	prefix=$( get_tag_prefix "${tag}" )
	label=$( get_tag_label "${tag}" )
	label_dir="${install_dir}${prefix}/.halcyon/${label}"

	expect_existing "${label_dir}/data-dir" || return 1

	local data_dir
	data_dir=$( <"${label_dir}/data-dir" ) || true
	if [[ -z "${data_dir}" ]]; then
		log_error 'Failed to read data directory file'
		return 1
	fi

	log "Installing app to ${prefix}"

	if ! copy_dir_into "${install_dir}${prefix}" "${HALCYON_ROOT}${prefix}"; then
		log_error 'Failed to copy app to root directory'
		return 1
	fi

	if (( HALCYON_KEEP_DEPENDENCIES )); then
		if ! ln -fs "${HALCYON_BASE}/sandbox/cabal.sandbox.config" \
			"${HALCYON_ROOT}${prefix}/cabal.sandbox.config"
		then
			log_error 'Failed to symlink sandbox config'
			return 1
		fi
	fi

	if [[ -f "${source_dir}/.halcyon/post-install-hook" ]]; then
		log 'Executing post-install hook'
		if ! HALCYON_INTERNAL_RECURSIVE=1 \
			"${source_dir}/.halcyon/post-install-hook" \
				"${tag}" "${source_dir}" "${install_dir}" "${data_dir}" 2>&1 | quote
		then
			log_error 'Failed to execute post-install hook'
			return 1
		fi
		log 'Post-install hook executed'
	fi

	log "Installed ${label}"
}
