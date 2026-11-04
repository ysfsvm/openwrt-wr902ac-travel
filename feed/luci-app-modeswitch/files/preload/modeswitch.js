'use strict';
'require baseclass';
'require fs';
'require poll';
'require ui';

/* Header indicator on every LuCI page: live position of the hardware mode
 * switch (and the active position when it was applied manually). */
return baseclass.extend({
	__init__() {
		this.update();
		poll.add(L.bind(this.update, this), 5);
	},

	update() {
		return L.resolveDefault(fs.exec_direct('/usr/sbin/modectl', [ 'brief' ], 'json'), null).then(st => {
			if (!st || !st.position) {
				ui.hideIndicator('modeswitch');
				return;
			}

			let text = _('Switch: %s').format(st.position_alias || st.position);
			if (st.current && st.current != st.position)
				text += ' (' + _('active: %s').format(st.current_alias || st.current) + ')';
			if (!st.follow)
				text += ' (' + _('not followed') + ')';

			ui.showIndicator('modeswitch', text,
				() => { location.href = L.url('admin/system/modeswitch'); },
				(st.current == st.position && st.follow) ? 'active' : 'inactive');
		});
	}
});
