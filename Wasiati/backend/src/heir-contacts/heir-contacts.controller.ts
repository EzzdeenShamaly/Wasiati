import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { HeirContactsService } from './heir-contacts.service';
import { CreateHeirContactDto, UpdateHeirContactDto } from './dto/heir-contact.dto';

@ApiTags('heir-contacts')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('wills/:willId/heir-contacts')
export class HeirContactsController {
  constructor(private heirContacts: HeirContactsService) {}

  @Get()
  list(@CurrentUser() user: { userId: string }, @Param('willId') willId: string) {
    return this.heirContacts.list(willId, user.userId);
  }

  @Post()
  create(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Body() body: CreateHeirContactDto,
  ) {
    return this.heirContacts.create(willId, user.userId, body);
  }

  @Patch(':id')
  update(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Param('id') id: string,
    @Body() body: UpdateHeirContactDto,
  ) {
    return this.heirContacts.update(willId, user.userId, id, body);
  }

  @Delete(':id')
  remove(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Param('id') id: string,
  ) {
    return this.heirContacts.remove(willId, user.userId, id);
  }
}
