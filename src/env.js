import Cookies from "js-cookie";

export const domain = "http://127.0.0.1:8000";
export const REACT_APP_API_KEY="http://127.0.0.1:8000"

const token = "";
const csrftoken = Cookies.get("csrftoken");
export const getheader = {
  Authorization: `token ${token}`,
};

export const postheader = {
  "X-CSRFToken": csrftoken,
};

export const posttokenheader = {
    Authorization: `token ${token}`,
    "X-CSRFToken": csrftoken,
  };