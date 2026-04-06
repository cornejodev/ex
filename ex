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
