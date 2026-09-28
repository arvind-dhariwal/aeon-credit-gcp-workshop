#!/usr/bin/env python3
"""CLI helper for Track 1 Notebook 05: Create, Assign, and Cleanup BigQuery Enterprise Reservation for BigQuery Property Graph."""

import argparse
import os
import time
import google.auth
from google.auth.transport.requests import AuthorizedSession


def get_session(project_id: str = "", location: str = "asia-southeast1"):
    creds, default_proj = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    proj = (
        project_id
        or os.environ.get("PROJECT_ID", "").strip()
        or os.environ.get("GOOGLE_CLOUD_PROJECT", "").strip()
        or default_proj
    )
    session = AuthorizedSession(creds)
    session.headers.update({"x-goog-user-project": proj})
    return proj, location, session


def render_html(html_str: str):
    try:
        from IPython import get_ipython
        from IPython.display import HTML, display

        if get_ipython() is not None:
            display(HTML(html_str))
    except Exception:
        pass


def setup_reservation(
    project_id: str,
    location: str,
    reservation_id: str = "acsm-graph-enterprise-res",
    baseline_slots: int = 0,
    max_slots: int = 500,
):
    PROJECT_ID, LOCATION, session = get_session(project_id, location)
    base_url = f"https://bigqueryreservation.googleapis.com/v1/projects/{PROJECT_ID}/locations/{LOCATION}"
    res_url = f"{base_url}/reservations/{reservation_id}"

    # 1. Create or Update Enterprise Reservation (Baseline = 0, Max Autoscale Slots = 500)
    res_payload = {
        "edition": "ENTERPRISE",
        "slotCapacity": baseline_slots,
        "ignoreIdleSlots": False,
        "autoscale": {
            "maxSlots": max_slots,
        },
    }

    get_resp = session.get(res_url)
    if get_resp.status_code == 404:
        create_resp = session.post(
            f"{base_url}/reservations?reservationId={reservation_id}",
            json=res_payload,
        )
        if create_resp.status_code in (200, 201):
            res_info = create_resp.json()
            res_action = "Created"
        else:
            print(f"⚠️ Reservation creation status ({create_resp.status_code}): {create_resp.text}")
            res_info = {}
            res_action = "Failed"
    elif get_resp.status_code == 200:
        patch_resp = session.patch(
            f"{res_url}?updateMask=slotCapacity,autoscale.maxSlots",
            json=res_payload,
        )
        res_info = patch_resp.json() if patch_resp.status_code == 200 else get_resp.json()
        res_action = "Verified / Updated"
    else:
        print(f"⚠️ Unexpected status checking reservation ({get_resp.status_code}): {get_resp.text}")
        res_info = {}
        res_action = "Error"

    # 2. Assign Reservation to `projects/{PROJECT_ID}` for `QUERY` jobs
    assign_url = f"{res_url}/assignments"
    existing_assigns = (
        session.get(f"{base_url}/reservations/-/assignments")
        .json()
        .get("assignments", [])
    )

    target_assignment = None
    other_query_assignment = None
    for a in existing_assigns:
        if a.get("jobType") == "QUERY":
            if f"/reservations/{reservation_id}/" in a.get("name", ""):
                target_assignment = a
            else:
                other_query_assignment = a

    if target_assignment:
        assign_action = "Already Assigned"
    elif other_query_assignment:
        # Move existing QUERY assignment to this reservation
        move_resp = session.post(
            f"https://bigqueryreservation.googleapis.com/v1/{other_query_assignment['name']}:move",
            json={
                "destinationId": f"projects/{PROJECT_ID}/locations/{LOCATION}/reservations/{reservation_id}"
            },
        )
        if move_resp.status_code == 200:
            target_assignment = move_resp.json()
            assign_action = "Moved Existing Assignment"
        else:
            print(f"⚠️ Move assignment status ({move_resp.status_code}): {move_resp.text}")
            assign_action = "Move Failed"
    else:
        create_assign_resp = session.post(
            assign_url,
            json={
                "assignee": f"projects/{PROJECT_ID}",
                "jobType": "QUERY",
            },
        )
        if create_assign_resp.status_code in (200, 201):
            target_assignment = create_assign_resp.json()
            assign_action = "Assigned"
        else:
            print(f"⚠️ Assignment creation status ({create_assign_resp.status_code}): {create_assign_resp.text}")
            assign_action = "Assignment Failed"

    # Brief pause so reservation assignment propagates before running Property Graph DDL/GQL
    if assign_action in ("Assigned", "Moved Existing Assignment"):
        time.sleep(3)

    capacity_console_url = f"https://console.cloud.google.com/bigquery/admin/reservations?project={PROJECT_ID}"

    print("==========================================================================")
    print(f"⚡ [Step 1.0 Outcome] BigQuery Enterprise Reservation (`{LOCATION}`)")
    print("==========================================================================")
    print(f"  • Reservation Resource : `{res_info.get('name', f'projects/{PROJECT_ID}/locations/{LOCATION}/reservations/{reservation_id}')}` ({res_action})")
    print(f"  • Edition              : `{res_info.get('edition', 'ENTERPRISE')}` (Required for BigQuery Property Graph / ISO GQL)")
    print(f"  • Baseline Slots       : `{res_info.get('slotCapacity', baseline_slots)}` slots ($0 idle baseline cost)")
    print(f"  • Max Autoscale Slots  : `{res_info.get('autoscale', {}).get('maxSlots', max_slots)}` slots")
    if target_assignment:
        print(f"  • Project Assignment   : `{target_assignment.get('name')}` ({assign_action})")
        print(f"  • Assignee & Job Type  : `{target_assignment.get('assignee', f'projects/{PROJECT_ID}')}` -> `jobType={target_assignment.get('jobType', 'QUERY')}`")
    print(f"  • Capacity Console URL : {capacity_console_url}")
    print("==========================================================================")

    render_html(
        f'<div style="margin-top:8px;padding:12px 16px;background:#e6f4ea;border-left:4px solid #137333;border-radius:4px;font-family:sans-serif;font-size:13px;line-height:1.6;">'
        f'⚡ <b>BigQuery Enterprise Reservation Active for Property Graph (`{reservation_id}`):</b><br>'
        f'• <b>Edition:</b> <code>ENTERPRISE</code> &nbsp;|&nbsp; <b>Baseline Slots:</b> <code>{baseline_slots}</code> &nbsp;|&nbsp; <b>Max Autoscale Slots:</b> <code>{max_slots}</code> &nbsp;|&nbsp; <b>Assigned Project:</b> <code>{PROJECT_ID} (QUERY)</code><br>'
        f'• <a href="{capacity_console_url}" target="_blank" rel="noopener noreferrer" style="color:#137333;font-weight:bold;">Open BigQuery Capacity Management Console ↗</a> '
        f'<i>(Remember to run <b>Step 9 Cleanup</b> at the end of this notebook to delete the reservation)</i>'
        f'</div>'
    )


def cleanup_reservation(
    project_id: str,
    location: str,
    reservation_id: str = "acsm-graph-enterprise-res",
):
    PROJECT_ID, LOCATION, session = get_session(project_id, location)
    base_url = f"https://bigqueryreservation.googleapis.com/v1/projects/{PROJECT_ID}/locations/{LOCATION}"
    res_url = f"{base_url}/reservations/{reservation_id}"

    print("==========================================================================")
    print(f"🧹 [Step 9 Cleanup] Deleting Enterprise Reservation & Assignment (`{LOCATION}`)")
    print("==========================================================================")

    # 1. Delete all assignments under the reservation first (required before deleting a reservation)
    assign_list_resp = session.get(f"{res_url}/assignments")
    if assign_list_resp.status_code == 200:
        assignments = assign_list_resp.json().get("assignments", [])
        if not assignments:
            print(f"  ℹ️ No active assignments found on `{reservation_id}`.")
        for a in assignments:
            a_name = a.get("name")
            del_a = session.delete(f"https://bigqueryreservation.googleapis.com/v1/{a_name}")
            if del_a.status_code in (200, 204, 404):
                print(f"  ✅ Deleted Reservation Assignment: `{a_name}` (Assignee: `{a.get('assignee')}`, JobType: `{a.get('jobType')}`)")
            else:
                print(f"  ⚠️ Failed to delete assignment `{a_name}` ({del_a.status_code}): {del_a.text}")
    elif assign_list_resp.status_code == 404:
        print(f"  ℹ️ Reservation `{reservation_id}` already deleted (no assignments to remove).")

    # 2. Delete the Enterprise Reservation
    del_res = session.delete(res_url)
    if del_res.status_code in (200, 204):
        print(f"  ✅ Deleted Enterprise Reservation: `projects/{PROJECT_ID}/locations/{LOCATION}/reservations/{reservation_id}`")
        print(f"  ✅ Project `{PROJECT_ID}` has been reverted to standard On-Demand query pricing.")
    elif del_res.status_code == 404:
        print(f"  ℹ️ Reservation `{reservation_id}` was already deleted.")
    else:
        print(f"  ⚠️ Failed to delete reservation `{reservation_id}` ({del_res.status_code}): {del_res.text}")
    print("==========================================================================")


def main():
    parser = argparse.ArgumentParser(description="BigQuery Enterprise Reservation Helper for Notebook 05")
    parser.add_argument(
        "command",
        nargs="?",
        choices=["setup", "cleanup"],
        help="Action to execute: setup or cleanup",
    )
    parser.add_argument(
        "--action",
        choices=["setup", "cleanup"],
        help="Action to execute: setup or cleanup",
    )
    parser.add_argument("--project", default="", help="GCP Project ID")
    parser.add_argument("--location", default="asia-southeast1", help="BigQuery region")
    parser.add_argument("--reservation-id", default="acsm-graph-enterprise-res", help="Reservation ID")
    parser.add_argument("--baseline-slots", type=int, default=0, help="Baseline slots (default: 0)")
    parser.add_argument("--max-slots", type=int, default=500, help="Autoscale max slots (default: 500)")
    args = parser.parse_args()

    action = args.action or args.command
    if action == "setup":
        setup_reservation(
            args.project,
            args.location,
            args.reservation_id,
            args.baseline_slots,
            args.max_slots,
        )
    elif action == "cleanup":
        cleanup_reservation(args.project, args.location, args.reservation_id)
    else:
        parser.error("Please specify either 'setup' or 'cleanup'")


if __name__ == "__main__":
    main()
