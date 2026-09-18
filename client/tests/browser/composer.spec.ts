import { expect, test } from "@playwright/test";

test("ordinary typing, Unicode and multiline insertion preserve the draft", async ({ page }) => {
  await page.goto("/tests/fixtures/composer.html");
  const box = page.getByRole("textbox", { name: "message in #fixture" });
  await box.pressSequentially("hello world! Voice 123.");
  await expect(box).toHaveValue("hello world! Voice 123.");
  await box.fill("");
  // Browser-level insertion is a regression guard, not a wtype/Wayland test.
  const text = "Café — hello 👋\nA second line, still a draft.";
  await page.keyboard.insertText(text);
  await expect(box).toHaveValue(text);
  expect(await page.evaluate(() => document.documentElement.dataset.submitted)).toBeUndefined();
});

test("plus offers Add file and the smile inserts emoji at the caret", async ({
  page,
}) => {
  await page.goto("/tests/fixtures/composer.html");
  const box = page.getByRole("textbox", { name: "message in #fixture" });
  await box.fill("hi");
  await page.getByRole("button", { name: "Add", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Add file…", exact: true }),
  ).toBeVisible();
  await page.keyboard.press("Escape");
  await box.focus();
  await box.evaluate((node) => {
    const field = node as HTMLTextAreaElement;
    field.setSelectionRange(2, 2);
  });
  await page.getByRole("button", { name: "Emoji", exact: true }).click();
  await page.getByRole("button", { name: "wave", exact: true }).click();
  await expect(box).toHaveValue("hi👋");
});
