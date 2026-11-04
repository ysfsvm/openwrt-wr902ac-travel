'use strict';
'require view';
'require dom';
'require fs';
'require poll';
'require ui';

const MODECTL = '/usr/sbin/modectl';
const EDIT_DIR = '/tmp/modeswitch-edit';
const FULL_REFRESH = 30; /* s between full status refreshes; `brief` is polled every 3 s */

const css = `
.ms-tiles { display:flex; flex-wrap:wrap; gap:1em; margin:.5em 0 1em; }
.ms-tile { flex:1 1 15em; min-width:14em; display:flex; flex-direction:column;
  border:2px solid rgba(128,128,128,.3); border-radius:6px; padding:.8em 1em; }
.ms-tile.switch { border-color:#1a73e8; }
.ms-tile.active { background:rgba(26,115,232,.09); }
.ms-num { font-size:.8em; opacity:.65; text-transform:uppercase; letter-spacing:.05em; }
.ms-alias { font-size:1.5em; font-weight:bold; margin:.1em 0; }
.ms-badges { min-height:1.6em; margin-bottom:.3em; }
.ms-badges .label { margin-right:.3em; }
.ms-desc { font-size:.9em; opacity:.8; margin-bottom:.6em; }
.ms-facts { font-size:.9em; margin:0 0 .8em; padding:0; list-style:none; flex:1; }
.ms-facts li { margin:.15em 0; }
.ms-facts b { display:inline-block; min-width:6em; opacity:.65; font-weight:normal; }
.ms-up { color:#2a8f2a; } .ms-down { color:#c33; }
.ms-actions .btn { margin:0 .3em .3em 0; }
.ms-meta { font-size:.8em; opacity:.6; }
.ms-bar { display:flex; flex-wrap:wrap; align-items:center; gap:.5em 1.5em; margin:.5em 0; }
.ms-bar label { display:flex; align-items:center; gap:.4em; cursor:pointer; }
`;

function getStatus() {
	return fs.exec_direct(MODECTL, [ 'status', '--json' ], 'json').catch(() => null);
}

function getBrief() {
	return fs.exec_direct(MODECTL, [ 'brief' ], 'json').catch(() => null);
}

function dname(m) {
	return m.alias || m.name;
}

function ago(epoch) {
	if (!epoch)
		return '-';
	const s = Math.max(0, Math.floor(Date.now() / 1000) - +epoch);
	if (s < 90) return _('just now');
	if (s < 5400) return _('%d min ago').format(Math.round(s / 60));
	if (s < 86400) return _('%d h ago').format(Math.round(s / 3600));
	return new Date(+epoch * 1000).toLocaleString();
}

function reachableAt(m) {
	const a = (m.summary?.addresses || []).map(a => a.split('/')[0]);
	return a.length ? a.join(', ') : null;
}

function briefKey(position, current, follow) {
	return [ position, current, !!follow ].join('|');
}

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load() {
		return getStatus();
	},

	runModectl(args, busyText) {
		ui.showModal(null, [ E('p', { 'class': 'spinning' }, busyText) ]);
		return fs.exec(MODECTL, args).then(res => {
			ui.hideModal();
			if (res.code != 0)
				throw new Error((res.stderr || res.stdout || _('modectl failed')).trim());
		}).catch(e => {
			ui.hideModal();
			/* a dropped connection while the network reloads is expected */
			ui.addNotification(null, E('p', e.message || _('The connection was interrupted while the configuration was applied. Reconnect if the device address changed.')),
				e.message ? 'danger' : 'warning');
		}).then(() => this.refresh());
	},

	confirm(title, body, button, action) {
		ui.showModal(title, [
			...body,
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
				E('button', { 'class': 'btn cbi-button-action important', 'click': action }, button)
			])
		]);
	},

	confirmApply(m) {
		const at = reachableAt(m), s = m.summary || {};
		this.confirm(_('Switch to %s?').format(dname(m)), [
			E('p', _('The network, Wi-Fi, firewall and DHCP configuration of %s is applied now.').format(dname(m))),
			at ? E('p', { 'class': 'alert-message notice' }, s.vlans
					? _('Afterwards this device is reachable only at %s, on the tagged management VLAN of the wired trunk. Reconnect there.').format(at)
					: _('Afterwards this device is reachable at %s. You may have to reconnect.').format(at))
			   : E('p', { 'class': 'alert-message warning' }, _('This position has no static address; the device gets its address from the network.')),
			E('p', _('It stays active until the switch is moved or the device reboots.'))
		], _('Apply'), () => this.runModectl([ 'apply', m.name ], _('Applying…')));
	},

	confirmReset(m) {
		this.confirm(_('Reset %s to its defaults?').format(dname(m)), [
			E('p', m.active
				? _('The configuration of this position is rebuilt from its defaults template and applied now. Your changes in this position are lost.')
				: _('The configuration of this position is rebuilt from its defaults template now. Your changes in this position are lost; it is applied the next time the switch is set here.'))
		], _('Reset'), () => this.runModectl([ 'reset', m.name ], _('Resetting…')));
	},

	editProfile(m, files) {
		const reads = [];
		files.forEach(f => {
			reads.push(L.resolveDefault(fs.read('/etc/config/' + f), ''));
			reads.push(L.resolveDefault(fs.read('/etc/modes/%s/%s'.format(m.name, f)), null));
		});

		const title = dname(m);
		return Promise.all(reads).then(data => {
			const panes = [], editors = {};

			files.forEach((f, i) => {
				const running = data[i * 2], profile = data[i * 2 + 1];
				const ro = E('textarea', { 'class': 'cbi-input-textarea', 'rows': 8, 'readonly': 'readonly', 'spellcheck': 'false',
					'style': 'width:100%; font-family:monospace; white-space:pre; opacity:.75' });
				const ed = E('textarea', { 'class': 'cbi-input-textarea', 'rows': 14, 'spellcheck': 'false',
					'style': 'width:100%; font-family:monospace; white-space:pre' });
				ro.value = running;
				ed.value = profile ?? '';
				editors[f] = { ed: ed, orig: ed.value };

				const state = profile == null ? _('(not built yet)')
					: (profile == running ? _('(identical to the running config)') : _('(differs from the running config)'));

				panes.push(E('div', { 'data-tab': f, 'data-tab-title': f }, [
					E('p', {}, [ E('strong', {}, _('Running config')), ' ', E('small', { 'style': 'opacity:.7' }, '/etc/config/' + f) ]),
					ro,
					E('p', { 'style': 'margin-top:1em' }, [
						E('strong', {}, _('%s configuration').format(title)), ' ',
						E('small', { 'style': 'opacity:.7' }, state), ' ',
						E('button', { 'class': 'btn cbi-button', 'click': ev => { ev.preventDefault(); ed.value = running; } }, _('Copy running config'))
					]),
					ed
				]));
			});

			const save = () => {
				const changed = files.filter(f => editors[f].ed.value != editors[f].orig);
				if (!changed.length) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('No changes.')), 'info');
					return;
				}
				ui.showModal(null, [ E('p', { 'class': 'spinning' }, _('Saving…')) ]);
				return changed.reduce((p, f) => p.then(() => {
					const tmp = '%s/%s.%s'.format(EDIT_DIR, m.name, f);
					return fs.write(tmp, editors[f].ed.value.replace(/\r\n/g, '\n').replace(/\n?$/, '\n'))
						.then(() => fs.exec(MODECTL, [ 'put', m.name, f, tmp ]))
						.then(res => {
							if (res.code != 0)
								throw new Error((res.stderr || res.stdout || '').trim() || _('modectl put failed'));
						});
				}), Promise.resolve()).then(() => {
					ui.hideModal();
					ui.addNotification(null, E('p', m.active
						? _('Saved and applied: %s').format(changed.join(', '))
						: _('Saved: %s. Applied the next time the switch is set to %s.').format(changed.join(', '), title)), 'info');
				}).catch(e => {
					ui.hideModal();
					ui.addNotification(null, E('p', e.message || _('The connection was interrupted while the configuration was applied.')), e.message ? 'danger' : 'warning');
				}).then(() => this.refresh());
			};

			const body = E('div', {}, panes);
			ui.showModal(_('%s configuration').format(title), [
				E('p', m.active
					? _('This position is active: its configuration is the running configuration. Saving here applies the change immediately.')
					: _('Copy the running config (or parts of it) into this position and adapt it. Each file is syntax-checked before it is stored.')),
				body,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
					E('button', { 'class': 'btn cbi-button-save important', 'click': save }, m.active ? _('Save & apply') : _('Save'))
				])
			], 'cbi-modal');
			ui.tabs.initTabGroup(body.childNodes);
		});
	},

	remember(st) {
		this.lastFull = Date.now();
		this.brief = st ? briefKey(st.position, st.current, st.follow_switch) : null;
	},

	refresh() {
		return getStatus().then(st => {
			this.remember(st);
			const node = document.getElementById('modeswitch-status');
			if (node)
				dom.content(node, this.renderStatus(st));
		});
	},

	tick() {
		if (Date.now() - (this.lastFull || 0) > FULL_REFRESH * 1000)
			return this.refresh();
		return getBrief().then(b => {
			if (b && briefKey(b.position, b.current, b.follow) != this.brief)
				return this.refresh();
		});
	},

	renderTile(st, m, i) {
		const s = m.summary || {}, facts = [];
		const fact = (k, v) => facts.push(E('li', {}, [ E('b', {}, k), v ]));

		fact(_('Address'), (s.addresses || []).length ? s.addresses.join(', ') : _('from DHCP'));
		if (s.wired_role == 'auto')
			fact(_('Uplink'), _('wired port; a joined Wi-Fi instead (wired port is LAN then)'));
		else if (s.wan)
			fact(_('Uplink'), s.wan);
		if (s.vlans)
			fact(_('Trunk'), _('VLAN %s, tagged').format(s.vlans.split(' ').join(', ')));
		fact(_('Wi-Fi'), (s.ssids || []).length ? s.ssids.join(', ') : _('off'));
		fact(_('DHCP'), s.dhcp ? _('serves addresses') : _('none'));

		if (m.active && st.uplink) {
			const u = st.uplink;
			fact(_('Uplink now'), u.up
				? E('span', { 'class': 'ms-up' }, _('%s up · %s via %s').format(u.iface == 'wwan' ? _('Wi-Fi') : (u.device || ''), u.address || '?', u.gateway || '?'))
				: E('span', { 'class': 'ms-down' }, _('down (%s)').format(u.device || 'wan')));
		}

		return E('div', { 'class': 'ms-tile' + (m.switch_here ? ' switch' : '') + (m.active ? ' active' : '') }, [
			E('div', { 'class': 'ms-num' }, '%d · %s'.format(i + 1, m.label || m.name)),
			E('div', { 'class': 'ms-alias' }, dname(m)),
			E('div', { 'class': 'ms-badges' }, [
				m.active ? E('span', { 'class': 'label notice' }, _('active')) : '',
				m.switch_here ? E('span', { 'class': 'label' }, _('switch is here')) : '',
				!m.has_profile ? E('span', { 'class': 'label warning' }, _('not built yet')) : ''
			]),
			E('div', { 'class': 'ms-desc' }, m.description || ''),
			E('ul', { 'class': 'ms-facts' }, facts),
			E('div', { 'class': 'ms-actions' }, [
				E('button', { 'class': 'btn cbi-button-apply', 'disabled': m.active ? '' : null,
					'title': m.active ? _('Already active') : _('Apply this position now'),
					'click': () => this.confirmApply(m) }, _('Apply')),
				E('button', { 'class': 'btn cbi-button-edit', 'click': () => this.editProfile(m, st.files) }, _('Edit…')),
				E('button', { 'class': 'btn cbi-button-reset', 'disabled': m.has_defaults ? null : '',
					'title': _('Rebuild from the defaults template'),
					'click': () => this.confirmReset(m) }, _('Reset'))
			]),
			E('div', { 'class': 'ms-meta' }, [
				m.name, ' · ',
				m.has_profile ? _('saved %s').format(ago(m.saved || m.generated)) : _('built from defaults on first use')
			])
		]);
	},

	renderStatus(st) {
		if (!st)
			return E('p', { 'class': 'alert-message warning' }, _('Could not read the mode switch status.'));

		const notes = [];
		if (st.follow_switch && st.position && st.current && st.position != st.current)
			notes.push(E('p', { 'class': 'alert-message notice' },
				_('%s was applied manually; the switch is at %s. Moving the switch or rebooting applies the switch position.')
					.format(st.current_alias || st.current, st.position_alias || st.position)));
		if (st.pending)
			notes.push(E('p', { 'class': 'alert-message warning' },
				_('There are unsaved changes to %s. Save & apply them on their pages; they are discarded when the position changes.').format(st.files.join(', '))));

		const follow = E('input', { 'type': 'checkbox', 'checked': st.follow_switch ? '' : null,
			'change': ev => this.runModectl([ 'follow', ev.target.checked ? 'on' : 'off' ], _('Saving…')) });

		return E([], [
			E('div', { 'class': 'ms-tiles' }, (st.modes || []).map((m, i) => this.renderTile(st, m, i))),
			E('div', { 'class': 'ms-bar' }, [
				E('label', {}, [ follow, _('Follow the hardware switch') ]),
				E('small', { 'style': 'opacity:.7' }, st.follow_switch
					? _('Moving the switch (and booting) applies its position.')
					: _('The switch is ignored; positions are only applied from here.'))
			]),
			...notes
		]);
	},

	render(st) {
		this.remember(st);
		poll.add(() => this.tick(), 3);

		return E([], [
			E('style', {}, css),
			E('h2', {}, _('Mode Switch')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Each position of the hardware switch has its own network, Wi-Fi, firewall and DHCP configuration. ' +
				  'Change the active one on the usual pages (Network, Wireless, …); every saved change is kept for that position. ' +
				  'Use Edit… to prepare another position. System settings and passwords are shared.')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'id': 'modeswitch-status' }, this.renderStatus(st))
			])
		]);
	}
});
