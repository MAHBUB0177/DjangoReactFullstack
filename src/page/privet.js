
import React from "react";
import { Navigate, useLocation } from "react-router-dom";

const Private = ({ children, ...rest }) => {
  const location = useLocation();
//   if (state?.data?.token) {
    // return children;
//   }
  return <Navigate to="/main" state={{ from: location }} />;
};

export default Private;