<div class="content-box" style="padding-bottom: 1.5em;">
    {{ partial("layout_partials/base_form",['fields':generalForm,'id':'frm_general']) }}
    <div class="col-md-12">
        <hr/>
        <button class="btn btn-primary" id="saveAct" type="button">
            <b>{{ lang._('Save') }}</b> <i id="saveAct_progress"></i>
        </button>
        <button class="btn btn-default" id="testAct" type="button">
            {{ lang._('Send test message') }} <i id="testAct_progress"></i>
        </button>
        <button class="btn btn-default" id="dailyAct" type="button">
            {{ lang._('Send daily summary now') }} <i id="dailyAct_progress"></i>
        </button>
        <p class="text-muted" style="margin-top: 1em;">
            {{ lang._('Save applies everything: the Monit checks and the daily summary cron job are created, enabled or disabled to match these switches. Save before testing.') }}
        </p>
    </div>
</div>

<script>
    $(document).ready(function () {
        mapDataToFormUI({'frm_general': "/api/telegramalerts/settings/get"}).done(function () {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        $("#saveAct").click(function () {
            saveFormToEndpoint("/api/telegramalerts/settings/set", 'frm_general', function () {
                $("#saveAct_progress").addClass("fa fa-spinner fa-pulse");
                ajaxCall("/api/telegramalerts/service/reconfigure", {}, function (data) {
                    $("#saveAct_progress").removeClass("fa fa-spinner fa-pulse");
                    if (data.status !== 'ok' || (data.warnings && data.warnings.length)) {
                        BootstrapDialog.show({
                            type: BootstrapDialog.TYPE_DANGER,
                            title: "{{ lang._('Telegram Alerts') }}",
                            message: $('<div/>').text((data.message || '') + ' ' + (data.warnings || []).join('; ')).html()
                        });
                    }
                });
            });
        });

        $("#testAct").click(function () {
            $("#testAct_progress").addClass("fa fa-spinner fa-pulse");
            ajaxCall("/api/telegramalerts/service/test", {}, function (data) {
                $("#testAct_progress").removeClass("fa fa-spinner fa-pulse");
                var ok = data.status === 'ok';
                BootstrapDialog.show({
                    type: ok ? BootstrapDialog.TYPE_SUCCESS : BootstrapDialog.TYPE_DANGER,
                    title: "{{ lang._('Telegram test') }}",
                    message: ok ? "{{ lang._('Message sent. Check Telegram.') }}"
                                : $('<div/>').text(data.message || 'unknown error').html()
                });
            });
        });

        $("#dailyAct").click(function () {
            $("#dailyAct_progress").addClass("fa fa-spinner fa-pulse");
            ajaxCall("/api/telegramalerts/service/daily", {}, function () {
                $("#dailyAct_progress").removeClass("fa fa-spinner fa-pulse");
            });
        });
    });
</script>
