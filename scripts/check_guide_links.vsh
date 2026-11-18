// Check guide links and fingerprints for documentation that points to source lines.
import encoding.utf8
import x.json2
import os
import strings

const fingerprint_path = '.github/guide-source-anchors.json'

fn heading_slug(text string) string {
	mut slug := strings.new_builder(text.len)
	mut pending_space := false
	for ch in utf8.to_lower(text.trim_left('#').trim_space()).runes() {
		if ch == ` ` {
			pending_space = true
		} else if ch in [`_`, `-`] || utf8.is_letter(ch) || utf8.is_number(ch) {
			if pending_space {
				slug.write_u8(`-`)
				pending_space = false
			}
			slug.write_rune(ch)
		}
	}
	if pending_space {
		slug.write_u8(`-`)
	}
	return slug.str()
}

fn link_targets(text string) []string {
	mut links := []string{}
	mut remaining := text
	for {
		start := remaining.index('[') or { break }
		remaining = remaining[start + 1..]
		close := remaining.index(']') or { break }
		label_end := close + 1
		if !remaining[label_end..].starts_with('(') {
			continue
		}
		target_start := label_end + 1
		end := remaining.index_after(')', target_start) or { continue }
		if end > target_start {
			links << remaining[target_start..end]
		}
		remaining = remaining[end + 1..]
	}
	return links
}

fn anchor_line(text string) bool {
	return text.len > 1 && text[0] == `L` && text[1] != `0` && text[1..].bytes().all(it.is_digit())
}

fn anchor_range(fragment string) ?(int, int) {
	start, end := fragment.split_once('-') or { fragment, fragment }
	if !anchor_line(start) || !anchor_line(end) {
		return none
	}
	return start[1..].int(), end[1..].int()
}

fn markdown_pages(directory string) ![]string {
	mut pages := os.ls(directory)!.filter(it.ends_with('.md'))
	pages.sort()
	return pages.map(os.join_path(directory, it))
}

fn project_relative(path string, root string) !string {
	prefix := root + os.path_separator
	if !path.starts_with(prefix) {
		return error('source anchor is outside this checkout')
	}
	return path[prefix.len..].replace(os.path_separator, '/')
}

fn collect(root string, mut errors []string) !map[string]string {
	mut pages := ['README.md']
	pages << markdown_pages('docs')!
	pages << markdown_pages(os.join_path('docs', 'guide'))!
	mut actual := map[string]string{}
	for page in pages {
		for i, text in os.read_lines(page)! {
			for target in link_targets(text) {
				if target.starts_with('http://') || target.starts_with('https://')
					|| target.starts_with('mailto:') {
					continue
				}
				file_part, fragment := target.split_once('#') or { target, '' }
				destination := if file_part == '' {
					os.real_path(page)
				} else if os.is_abs_path(file_part) {
					os.real_path(file_part)
				} else {
					os.real_path(os.join_path(os.dir(page), file_part))
				}
				location := '${page}:${i + 1}'
				if !os.exists(destination) {
					errors << '${location}: missing ${target}'
					continue
				}
				if fragment == '' {
					continue
				}
				if start, end := anchor_range(fragment) {
					if !os.is_file(destination) {
						errors << '${location}: line anchor on directory ${target}'
						continue
					}
					lines := os.read_lines(destination)!
					if start < 1 || start > end || end > lines.len {
						errors << '${location}: line outside ${target}'
						continue
					}
					key := project_relative(destination, root)!
					actual['${key}#${fragment}'] = lines[start - 1..end].join('\n')
				} else if destination.ends_with('.md') {
					lines := os.read_lines(destination)!
					if !lines.any(it.starts_with('#') && heading_slug(it) == fragment) {
						errors << '${location}: missing heading ${target}'
					}
				}
			}
		}
	}
	return actual
}

fn verify(args []string) ! {
	if args == ['--help'] || args == ['-h'] {
		println('usage: v run scripts/check_guide_links.vsh [--refresh]\n\nUse --refresh after reviewing moved code and updating the guide links.')
		return
	}
	refresh := args == ['--refresh']
	if args.len != 0 && !refresh {
		return error('usage: v run scripts/check_guide_links.vsh [--refresh]')
	}
	root := os.real_path(os.dir(@DIR))
	os.chdir(root)!
	mut errors := []string{}
	actual := collect(root, mut errors)!
	mut keys := actual.keys()
	keys.sort()
	if refresh {
		if errors.len > 0 {
			return error(errors.join('\n'))
		}
		encoded := keys.map('  ${json2.encode(it)}: ${json2.encode(actual[it])}')
		text := if encoded.len == 0 { '{}\n' } else { '{\n${encoded.join(',\n')}\n}\n' }
		os.write_file(fingerprint_path, text)!
		println('Recorded ${actual.len} source anchors')
		return
	}
	expected := if os.is_file(fingerprint_path) {
		json2.decode[map[string]string](os.read_file(fingerprint_path)!)!
	} else {
		map[string]string{}
	}
	for key in keys {
		if key !in expected {
			errors << 'untracked source anchor ${key}'
		} else if expected[key] != actual[key] {
			errors << 'stale source anchor ${key}'
		}
	}
	for key in expected.keys().sorted() {
		if key !in actual {
			errors << 'unused source anchor ${key}'
		}
	}
	if errors.len > 0 {
		return error(errors.join('\n'))
	}
	println('Guide links valid; ${actual.len} source anchors match')
}

verify(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
