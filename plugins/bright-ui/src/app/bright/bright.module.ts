import {NgModule} from '@angular/core';
import {CommonModule} from '@angular/common';
import {BrightComponent} from "./bright.component";
import {DevicesJobsViewModule} from "./views/devices-jobs-view/devices-jobs-view.module";
import {HttpClientModule} from "@angular/common/http";
import {RouterModule} from "@angular/router";
import {BrightRoutes} from "./bright.routes";


@NgModule({
  declarations: [BrightComponent],
  exports: [
    BrightComponent
  ],
  imports: [
    CommonModule,
    HttpClientModule,
    RouterModule.forChild(BrightRoutes),
    DevicesJobsViewModule
  ]
})
export class BrightModule {
}
