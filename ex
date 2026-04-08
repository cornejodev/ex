from playwright.sync_api import Page
from page_funcs.landing import logon
from page_funcs.chatbot import (
    setup_chatbot_config,
    open_chatbot_chat,
    assert_response_to_prompt,
)


def test_ts_001(page: Page) -> None:
    logon(page)
    setup_chatbot_config(page)
    open_chatbot_chat(page)
    assert_response_to_prompt(page, sheet_name="ts_001_structured_response")


====


from pathlib import Path
from playwright.sync_api import Page, expect
from utils.excel_checker import process_excel_chat_assertions


def setup_chatbot_config(page: Page) -> None:
    claim_input = page.locator("div.cai-field", has_text="Claim Number").locator("input")
    claim_input.wait_for(state="visible", timeout=60_000)
    claim_input.fill("001000-586407-WC-01")

    dropdown = page.locator("div.cai-field", has_text="Source System").locator("select")
    dropdown.select_option("luminos")

    page.get_by_role("checkbox", name="Show Diagnostic Information").check()
    page.get_by_role("button", name="Submit").click()


def open_chatbot_chat(page: Page) -> None:
    chatbot_btn = page.locator(".cai-bot-icon")
    chatbot_btn.wait_for(state="visible", timeout=60_000)
    chatbot_btn.click(force=True)

    chat_input = page.get_by_placeholder("Type your response...")
    chat_input.wait_for(state="visible", timeout=60_000)


def input_prompt_to_chatbot_textbox(page: Page, prompt: str) -> None:
    chat_input = page.get_by_placeholder("Type your response...")
    chat_input.wait_for(state="visible", timeout=60_000)
    chat_input.fill(prompt)


def send_prompt_to_chatbot(page: Page) -> None:
    send_prompt_btn = page.locator(".cai-send-btn")
    send_prompt_btn.click()


def get_latest_chatbot_response(page: Page) -> str:
    chatbot_response = page.locator(".cai-streamed-response").last
    chatbot_response.wait_for(state="visible", timeout=60_000)
    return (chatbot_response.inner_text() or "").strip()


def assert_response_to_prompt(page: Page, sheet_name: str) -> None:
    excel_path = Path("test_data") / "qa_automation_test_data_input_matrix.xlsx"

    process_excel_chat_assertions(
        page=page,
        excel_path=excel_path,
        sheet_name=sheet_name,
        prompt_sender=input_prompt_to_chatbot_textbox,
        send_action=send_prompt_to_chatbot,
        response_reader=get_latest_chatbot_response,
    )




===

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Callable
import pandas as pd


def _timestamp() -> str:
    return datetime.now().strftime("%d_%m_%Y_%H_%M_%S")


def _ensure_results_root() -> Path:
    results_root = Path("test-results") / f"run_{_timestamp()}"
    results_root.mkdir(parents=True, exist_ok=True)
    return results_root


def _load_sheet(excel_path: Path, sheet_name: str) -> pd.DataFrame:
    df = pd.read_excel(excel_path, sheet_name=sheet_name)

    required_columns = {"tc_id", "input", "expected_output"}
    missing = required_columns - set(df.columns)
    if missing:
        raise ValueError(
            f"Missing required columns in sheet '{sheet_name}': {sorted(missing)}"
        )

    return df.fillna("")


def _save_bug_report(results_root: Path, failed_rows: list[dict]) -> None:
    if not failed_rows:
        return

    bug_report_path = results_root / "bug_report.xlsx"
    report_df = pd.DataFrame(
        failed_rows,
        columns=["tc_id", "input", "expected_output", "actual_output", "status"],
    )
    report_df.to_excel(bug_report_path, index=False)


def process_excel_chat_assertions(
    page,
    excel_path: Path,
    sheet_name: str,
    prompt_sender: Callable,
    send_action: Callable,
    response_reader: Callable,
) -> None:
    df = _load_sheet(excel_path, sheet_name)
    results_root = _ensure_results_root()

    failed_rows: list[dict] = []

    for _, row in df.iterrows():
        tc_id = str(row["tc_id"]).strip()
        user_input = str(row["input"]).strip()
        expected_output = str(row["expected_output"]).strip()

        print(f"Executing test ID: {tc_id} ...")

        actual_output = ""
        evidence_dir = results_root / f"tc_{tc_id}_fail_evidence"

        try:
            prompt_sender(page, user_input)
            send_action(page)

            actual_output = response_reader(page)

            if expected_output not in actual_output:
                raise AssertionError(
                    f"Expected output not found.\n"
                    f"Expected: {expected_output}\n"
                    f"Actual: {actual_output}"
                )

            print(f"Test ID {tc_id}: PASSED")

        except Exception as exc:
            print(f"Test ID {tc_id}: FAILED")
            print(str(exc))

            evidence_dir.mkdir(parents=True, exist_ok=True)

            try:
                page.screenshot(
                    path=str(evidence_dir / f"tc_{tc_id}_failure.png"),
                    full_page=True,
                )
            except Exception:
                pass

            try:
                html = page.content()
                (evidence_dir / f"tc_{tc_id}_dom.html").write_text(
                    html,
                    encoding="utf-8",
                )
            except Exception:
                pass

            failed_rows.append(
                {
                    "tc_id": tc_id,
                    "input": user_input,
                    "expected_output": expected_output,
                    "actual_output": actual_output,
                    "status": "failed",
                }
            )

    _save_bug_report(results_root, failed_rows)

    if failed_rows:
        failed_ids = ", ".join(str(row["tc_id"]) for row in failed_rows)
        raise AssertionError(
            f"{len(failed_rows)} Excel-driven validation(s) failed. "
            f"Failed test IDs: {failed_ids}"
        )
====

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError


def get_latest_chatbot_response(page: Page) -> str:
    # 👇 1. wait for "Generating response..." to disappear
    generating = page.get_by_text("Generating response...")

    try:
        generating.wait_for(state="visible", timeout=10_000)
    except PlaywrightTimeoutError:
        pass

    try:
        generating.wait_for(state="hidden", timeout=60_000)
    except PlaywrightTimeoutError:
        pass

    # 👇 2. now safely get final response
    chatbot_response = page.locator(".cai-streamed-response").last
    chatbot_response.wait_for(state="visible", timeout=60_000)

    return (chatbot_response.inner_text() or "").strip()


===


import time
from playwright.sync_api import Page, TimeoutError as PlaywrightTimeoutError


def get_latest_chatbot_response(page: Page) -> str:
    chatbot_response = page.locator(".cai-streamed-response").last
    chatbot_response.wait_for(state="visible", timeout=60_000)

    generating = page.get_by_text("Generating response...")

    try:
        generating.wait_for(state="visible", timeout=10_000)
    except PlaywrightTimeoutError:
        pass

    try:
        generating.wait_for(state="hidden", timeout=60_000)
    except PlaywrightTimeoutError:
        pass

    timeout_seconds = 60
    poll_interval = 1.0
    stable_checks_needed = 3

    end_time = time.time() + timeout_seconds
    previous_text = ""
    stable_checks = 0

    while time.time() < end_time:
        current_text = (chatbot_response.inner_text() or "").strip()

        if current_text and current_text == previous_text:
            stable_checks += 1
            if stable_checks >= stable_checks_needed:
                return current_text
        else:
            stable_checks = 0
            previous_text = current_text

        time.sleep(poll_interval)

    return (chatbot_response.inner_text() or "").strip()

==

def export_diagnostics_excel_to_failure_folder(page: Page, evidence_dir: Path) -> Path:
    evidence_dir.mkdir(parents=True, exist_ok=True)

    export_button = page.get_by_role("button", name="Export To Excel")
    export_button.wait_for(state="visible", timeout=60_000)
    expect(export_button).to_be_enabled(timeout=60_000)

    with page.expect_download() as download_info:
        export_button.click()

    download = download_info.value
    save_path = evidence_dir / download.suggested_filename
    download.save_as(str(save_path))

    return save_path

===

except Exception as exc:
    print(f"Test ID {tc_id}: FAILED")
    print(str(exc))

    evidence_dir.mkdir(parents=True, exist_ok=True)

    try:
        page.screenshot(
            path=str(evidence_dir / f"tc_{tc_id}_failure.png"),
            full_page=True,
        )
    except Exception:
        pass

    try:
        html = page.content()
        (evidence_dir / f"tc_{tc_id}_dom.html").write_text(html, encoding="utf-8")
    except Exception:
        pass

    try:
        exported_file = export_diagnostics_excel_to_failure_folder(page, evidence_dir)
        print(f"Saved diagnostics export to: {exported_file}")
    except Exception as export_error:
        print(f"Could not export diagnostics for TC {tc_id}: {export_error}")

    failed_rows.append(
        {
            "tc_id": tc_id,
            "input": user_input,
            "expected_output": expected_output,
            "actual_output": actual_output,
            "status": "failed",
        }
    )

==

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Callable

import pandas as pd

from utils.diagnostics_exporter import export_diagnostics_excel_to_failure_folder


def _timestamp() -> str:
    return datetime.now().strftime("%d_%m_%Y_%H_%M_%S")


def _ensure_results_root() -> Path:
    results_root = Path("test-results") / f"run_{_timestamp()}"
    results_root.mkdir(parents=True, exist_ok=True)
    return results_root


def _load_sheet(excel_path: Path, sheet_name: str) -> pd.DataFrame:
    df = pd.read_excel(excel_path, sheet_name=sheet_name)

    required_columns = {"tc_id", "input", "expected_output"}
    missing = required_columns - set(df.columns)
    if missing:
        raise ValueError(
            f"Missing required columns in sheet '{sheet_name}': {sorted(missing)}"
        )

    return df.fillna("")


def _save_execution_report(
    results_root: Path,
    failed_rows: list[dict],
    total_count: int,
    passed_count: int,
    failed_count: int,
    start_dt: datetime,
    end_dt: datetime,
    source_sheet_name: str,
    source_excel_path: Path,
) -> None:
    report_path = results_root / "bug_report.xlsx"

    duration_seconds = round((end_dt - start_dt).total_seconds(), 2)
    pass_rate_percent = round((passed_count / total_count) * 100, 2) if total_count else 0.0

    failed_ids = ", ".join(str(row["tc_id"]) for row in failed_rows) if failed_rows else ""

    bug_df = pd.DataFrame(
        failed_rows,
        columns=["tc_id", "input", "expected_output", "actual_output", "status"],
    )

    summary_df = pd.DataFrame(
        [
            {"metric": "source_excel_file", "value": str(source_excel_path)},
            {"metric": "source_sheet_name", "value": source_sheet_name},
            {"metric": "total_test_cases", "value": total_count},
            {"metric": "passed_test_cases", "value": passed_count},
            {"metric": "failed_test_cases", "value": failed_count},
            {"metric": "pass_rate_percent", "value": pass_rate_percent},
            {"metric": "started_at", "value": start_dt.strftime("%d_%m_%Y %H:%M:%S")},
            {"metric": "finished_at", "value": end_dt.strftime("%d_%m_%Y %H:%M:%S")},
            {"metric": "duration_seconds", "value": duration_seconds},
            {"metric": "failed_test_ids", "value": failed_ids},
        ]
    )

    with pd.ExcelWriter(report_path, engine="openpyxl") as writer:
        bug_df.to_excel(writer, sheet_name="bug_report", index=False)
        summary_df.to_excel(writer, sheet_name="summary", index=False)


def process_excel_chat_assertions(
    page,
    excel_path: Path,
    sheet_name: str,
    prompt_sender: Callable,
    send_action: Callable,
    response_reader: Callable,
) -> None:
    df = _load_sheet(excel_path, sheet_name)
    results_root = _ensure_results_root()

    failed_rows: list[dict] = []

    # --- counters / execution tracking ---
    start_dt = datetime.now()
    total_count = len(df)
    passed_count = 0
    failed_count = 0

    print("Execution started")
    print(f"Source Excel: {excel_path}")
    print(f"Source sheet: {sheet_name}")
    print(f"Total test cases to execute: {total_count}")

    for _, row in df.iterrows():
        tc_id = str(row["tc_id"]).strip()
        user_input = str(row["input"]).strip()
        expected_output = str(row["expected_output"]).strip()

        print(f"Executing test ID: {tc_id} ...")

        actual_output = ""
        evidence_dir = results_root / f"tc_{tc_id}_fail_evidence"

        try:
            prompt_sender(page, user_input)
            send_action(page)

            actual_output = response_reader(page)

            if expected_output not in actual_output:
                raise AssertionError(
                    f"Expected output not found.\n"
                    f"Expected: {expected_output}\n"
                    f"Actual: {actual_output}"
                )

            passed_count += 1
            print(f"Test ID {tc_id}: PASSED")

        except Exception as exc:
            failed_count += 1
            print(f"Test ID {tc_id}: FAILED")
            print(str(exc))

            evidence_dir.mkdir(parents=True, exist_ok=True)

            try:
                page.screenshot(
                    path=str(evidence_dir / f"tc_{tc_id}_failure.png"),
                    full_page=True,
                )
            except Exception:
                pass

            try:
                html = page.content()
                (evidence_dir / f"tc_{tc_id}_dom.html").write_text(
                    html,
                    encoding="utf-8",
                )
            except Exception:
                pass

            try:
                exported_file = export_diagnostics_excel_to_failure_folder(
                    page,
                    evidence_dir,
                )
                print(f"Saved diagnostics export to: {exported_file}")
            except Exception as export_error:
                print(f"Could not export diagnostics for TC {tc_id}: {export_error}")

            failed_rows.append(
                {
                    "tc_id": tc_id,
                    "input": user_input,
                    "expected_output": expected_output,
                    "actual_output": actual_output,
                    "status": "failed",
                }
            )

    end_dt = datetime.now()

    # --- helper call happens here ---
    _save_execution_report(
        results_root=results_root,
        failed_rows=failed_rows,
        total_count=total_count,
        passed_count=passed_count,
        failed_count=failed_count,
        start_dt=start_dt,
        end_dt=end_dt,
        source_sheet_name=sheet_name,
        source_excel_path=excel_path,
    )

    print("Execution summary")
    print(f"Total: {total_count}")
    print(f"Passed: {passed_count}")
    print(f"Failed: {failed_count}")
    print(f"Duration (s): {(end_dt - start_dt).total_seconds():.2f}")

    if failed_rows:
        failed_ids = ", ".join(str(row["tc_id"]) for row in failed_rows)
        raise AssertionError(
            f"{len(failed_rows)} Excel-driven validation(s) failed. "
            f"Failed test IDs: {failed_ids}"
        )

====

import logging
import sys


def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)

    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)

    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(logging.INFO)

    formatter = logging.Formatter(
        fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%d-%m-%Y %H:%M:%S",
    )
    handler.setFormatter(formatter)

    logger.addHandler(handler)
    logger.propagate = False

    return logger

===

total_seconds = (end_dt - start_dt).total_seconds()
duration_seconds = round(total_seconds, 2)
duration_minutes = round(total_seconds / 60, 2)

minutes = int(total_seconds // 60)
seconds = int(total_seconds % 60)
duration_human = f"{minutes}m {seconds}s"




summary_df = pd.DataFrame(
    [
        {"metric": "source_excel_file", "value": str(source_excel_path)},
        {"metric": "source_sheet_name", "value": source_sheet_name},
        {"metric": "total_test_cases", "value": total_count},
        {"metric": "passed_test_cases", "value": passed_count},
        {"metric": "failed_test_cases", "value": failed_count},
        {"metric": "pass_rate_percent", "value": pass_rate_percent},
        {"metric": "started_at", "value": start_dt.strftime("%d_%m_%Y %H:%M:%S")},
        {"metric": "finished_at", "value": end_dt.strftime("%d_%m_%Y %H:%M:%S")},
        {"metric": "duration_seconds", "value": duration_seconds},
        {"metric": "duration_minutes", "value": duration_minutes},
        {"metric": "duration_human", "value": duration_human},
        {"metric": "failed_test_ids", "value": failed_ids},
    ]
)

import math

minutes = math.floor(total_seconds / 60)
seconds = round(total_seconds % 60, 2)

===

[pytest]
log_cli = true
log_cli_level = INFO
log_cli_format = %(asctime)s | %(levelname)-8s | %(name)s | %(message)s
log_cli_date_format = %d-%m-%Y %H:%M:%S
log_file = test_results/execution.log
log_file_level = INFO

====


log_cli = true
log_cli_level = INFO
log_cli_format = %(asctime)s | %(levelname)-8s | %(name)s | %(message)s
log_cli_date_format = %d-%m-%Y %H:%M:%S
log_file = test_results/execution.log
log_file_level = INFO
log_file_format = %(asctime)s | %(levelname)-8s | %(name)s | %(message)s
log_file_date_format = %d-%m-%Y %H:%M:%S



def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    return logger



=====


=IF(ISNUMBER(SEARCH("," & D2 & ",", "," & SUBSTITUTE($U$1," ","") & ",")),"Failed","")
